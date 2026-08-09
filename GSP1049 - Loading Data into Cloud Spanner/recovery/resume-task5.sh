#!/usr/bin/env bash
set -Eeuo pipefail

INSTANCE_ID="banking-instance"
DATABASE_ID="banking-db"
BACKUP_NAME="banking-backup-001"
DATAFLOW_JOB="spanner-load"
MANIFEST="gs://spls/gsp1049/manifest.json"

C_RESET='\033[0m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_RED='\033[1;31m'
say(){ printf "\n${C_CYAN}==> %s${C_RESET}\n" "$*"; }
ok(){ printf "${C_GREEN}✓ %s${C_RESET}\n" "$*"; }
warn(){ printf "${C_YELLOW}! %s${C_RESET}\n" "$*"; }
die(){ printf "${C_RED}ERROR: %s${C_RESET}\n" "$*" >&2; exit 1; }
checkpoint(){
  printf "\nKlik ${C_GREEN}Check my progress${C_RESET} untuk: ${C_CYAN}%s${C_RESET}\n" "$1"
  while true; do
    read -r -p "Sudah HIJAU? ketik y lalu Enter: " a
    case "${a,,}" in y|yes|ya|iya) break;; *) warn "Belum hijau; cek lagi.";; esac
  done
}

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die "Project ID tidak terdeteksi."

ZONE="$(curl -fsS --connect-timeout 1 --max-time 2 -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/project/attributes/google-compute-default-zone 2>/dev/null || true)"
REGION="$(curl -fsS --connect-timeout 1 --max-time 2 -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/project/attributes/google-compute-default-region 2>/dev/null || true)"
[[ -n "$ZONE" ]] || { ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"; [[ "$ZONE" == "(unset)" ]] && ZONE=""; }
[[ -n "$REGION" ]] || { REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"; [[ "$REGION" == "(unset)" ]] && REGION=""; }
[[ -n "$REGION" || -z "$ZONE" ]] || REGION="${ZONE%-*}"
if [[ -z "$REGION" ]]; then
  CFG="$(gcloud spanner instances describe "$INSTANCE_ID" --format='value(config)' 2>/dev/null || true)"
  CFG="${CFG##*/}"
  [[ "$CFG" == regional-* ]] && REGION="${CFG#regional-}"
fi
[[ -n "$REGION" ]] || die "Region tidak terdeteksi."

BUCKET="gs://${PROJECT_ID}"
TMP_PATH="${BUCKET}/tmp"
printf "Project: %s\nRegion : %s\n" "$PROJECT_ID" "$REGION"

say "FIX — menyiapkan Dataflow worker service account"
gcloud services enable compute.googleapis.com dataflow.googleapis.com iam.googleapis.com --quiet
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
WORKER_SA=""

for _ in {1..12}; do
  if gcloud iam service-accounts describe "$DEFAULT_SA" --project="$PROJECT_ID" >/dev/null 2>&1; then
    WORKER_SA="$DEFAULT_SA"; break
  fi
  sleep 1
done

if [[ -z "$WORKER_SA" ]]; then
  WORKER_SA="$(gcloud iam service-accounts list --project="$PROJECT_ID" --filter='disabled:false' \
    --format='value(email)' 2>/dev/null | grep -Ev 'gcp-sa-|cloudservices\.gserviceaccount\.com$' | head -n1 || true)"
fi

if [[ -z "$WORKER_SA" ]]; then
  WORKER_SA="gsp1049-dataflow-worker@${PROJECT_ID}.iam.gserviceaccount.com"
  gcloud iam service-accounts create gsp1049-dataflow-worker --project="$PROJECT_ID" \
    --display-name="GSP1049 Dataflow Worker" --quiet
fi

DISABLED="$(gcloud iam service-accounts describe "$WORKER_SA" --project="$PROJECT_ID" --format='value(disabled)' 2>/dev/null || true)"
if [[ "$DISABLED" == "True" || "$DISABLED" == "true" ]]; then
  gcloud iam service-accounts enable "$WORKER_SA" --project="$PROJECT_ID" --quiet
fi
ok "Worker SA: $WORKER_SA"

for ROLE in roles/dataflow.worker roles/storage.objectAdmin roles/spanner.databaseUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${WORKER_SA}" \
    --role="$ROLE" --condition=None --quiet >/dev/null 2>&1 || true
done

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"
if [[ -n "$ACTIVE_ACCOUNT" ]]; then
  if [[ "$ACTIVE_ACCOUNT" == *.gserviceaccount.com ]]; then MEMBER="serviceAccount:${ACTIVE_ACCOUNT}"; else MEMBER="user:${ACTIVE_ACCOUNT}"; fi
  gcloud iam service-accounts add-iam-policy-binding "$WORKER_SA" --project="$PROJECT_ID" \
    --member="$MEMBER" --role=roles/iam.serviceAccountUser --quiet >/dev/null 2>&1 || true
fi

if ! gcloud storage buckets describe "$BUCKET" >/dev/null 2>&1; then
  gcloud storage buckets create "$BUCKET" --location="$REGION" --quiet
fi
touch emptyfile
gcloud storage cp emptyfile "${TMP_PATH}/emptyfile" --quiet >/dev/null

say "TASK 5 — launch Dataflow"
JOB_ID="$(gcloud dataflow jobs list --region="$REGION" --filter="name=$DATAFLOW_JOB" \
  --sort-by='~createTime' --limit=1 --format='value(id)' 2>/dev/null || true)"
STATE=""
[[ -z "$JOB_ID" ]] || STATE="$(gcloud dataflow jobs describe "$JOB_ID" --region="$REGION" --format='value(currentState)' 2>/dev/null || true)"

case "$STATE" in
  JOB_STATE_RUNNING|JOB_STATE_PENDING|JOB_STATE_QUEUED|JOB_STATE_DONE)
    warn "Reuse existing job: $STATE"
    ;;
  *)
    gcloud dataflow jobs run "$DATAFLOW_JOB" \
      --gcs-location="gs://dataflow-templates-${REGION}/latest/GCS_Text_to_Cloud_Spanner" \
      --region="$REGION" \
      --staging-location="$TMP_PATH" \
      --worker-machine-type="e2-medium" \
      --service-account-email="$WORKER_SA" \
      --parameters="instanceId=${INSTANCE_ID},databaseId=${DATABASE_ID},importManifest=${MANIFEST}" \
      --quiet
    ;;
esac

say "Menunggu Dataflow JOB_STATE_DONE"
while true; do
  JOB_ID="$(gcloud dataflow jobs list --region="$REGION" --filter="name=$DATAFLOW_JOB" \
    --sort-by='~createTime' --limit=1 --format='value(id)' 2>/dev/null || true)"
  [[ -n "$JOB_ID" ]] || { sleep 2; continue; }
  STATE="$(gcloud dataflow jobs describe "$JOB_ID" --region="$REGION" --format='value(currentState)' 2>/dev/null || true)"
  printf '\rStatus: %-28s' "$STATE"
  case "$STATE" in
    JOB_STATE_DONE) printf '\n'; ok "Dataflow sukses."; break;;
    JOB_STATE_FAILED|JOB_STATE_CANCELLED|JOB_STATE_DRAINED) printf '\n'; die "Dataflow gagal: $STATE";;
  esac
  sleep 5
done

checkpoint "Load data using Dataflow"

gcloud spanner databases execute-sql "$DATABASE_ID" --instance="$INSTANCE_ID" \
  --sql="SELECT COUNT(*) AS CustomerCount FROM Customer"

say "TASK 6 — backup"
if gcloud spanner backups describe "$BACKUP_NAME" --instance="$INSTANCE_ID" >/dev/null 2>&1; then
  warn "Backup sudah ada."
else
  EXPIRE_TIME="$(date -u -d '+1 year' +'%Y-%m-%dT%H:%M:%SZ')"
  gcloud spanner backups create "$BACKUP_NAME" --instance="$INSTANCE_ID" \
    --database="$DATABASE_ID" --expiration-date="$EXPIRE_TIME" --async --quiet
fi
ok "Selesai."
