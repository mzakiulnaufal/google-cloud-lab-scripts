#!/usr/bin/env bash
set -Eeuo pipefail

# GSP1049 - Loading Data into Google Cloud Spanner
# Runs each scored objective in sequence and waits for your manual
# "Check my progress" confirmation before continuing.

INSTANCE_ID="banking-instance"
DATABASE_ID="banking-db"
TABLE_NAME="Customer"
BACKUP_NAME="banking-backup-001"
DATAFLOW_JOB="spanner-load"
MANIFEST="gs://spls/gsp1049/manifest.json"

C_RESET='\033[0m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_RED='\033[1;31m'

say()  { printf "\n${C_CYAN}==> %s${C_RESET}\n" "$*"; }
ok()   { printf "${C_GREEN}✓ %s${C_RESET}\n" "$*"; }
warn() { printf "${C_YELLOW}! %s${C_RESET}\n" "$*"; }
die()  { printf "${C_RED}ERROR: %s${C_RESET}\n" "$*" >&2; exit 1; }

checkpoint() {
  local objective="$1"
  printf "\n${C_YELLOW}------------------------------------------------------------${C_RESET}\n"
  printf "Buka tab lab -> klik ${C_GREEN}Check my progress${C_RESET} untuk:\n"
  printf "  ${C_CYAN}%s${C_RESET}\n" "$objective"
  printf "Script TIDAK akan mengerjakan objective berikutnya sebelum kamu konfirmasi.\n"
  while true; do
    read -r -p "Sudah HIJAU? ketik y lalu Enter: " answer
    case "${answer,,}" in
      y|yes|ya|iya) ok "Objective dikonfirmasi HIJAU."; break ;;
      *) warn "Belum dikonfirmasi. Cek progress lagi, lalu ketik y jika sudah hijau." ;;
    esac
  done
}

row_exists() {
  local id="$1"
  gcloud spanner databases execute-sql "$DATABASE_ID" \
    --instance="$INSTANCE_ID" \
    --sql="SELECT CustomerId FROM Customer WHERE CustomerId='$id'" 2>/dev/null \
    | grep -Fq "$id"
}

# -----------------------------------------------------------------------------
# Detect project / location without participant-specific hardcoding.
# -----------------------------------------------------------------------------
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die "Project ID tidak terdeteksi dari gcloud config."

gcloud config set project "$PROJECT_ID" --quiet >/dev/null

metadata_attr() {
  local key="$1"
  curl -fsS --connect-timeout 1 --max-time 2 \
    -H 'Metadata-Flavor: Google' \
    "http://metadata.google.internal/computeMetadata/v1/project/attributes/${key}" 2>/dev/null || true
}

ZONE="$(metadata_attr google-compute-default-zone)"
REGION="$(metadata_attr google-compute-default-region)"

if [[ -z "$ZONE" ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
  [[ "$ZONE" == "(unset)" ]] && ZONE=""
fi

if [[ -z "$REGION" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
  [[ "$REGION" == "(unset)" ]] && REGION=""
fi

# Project metadata is more reliable than the Cloud Shell VM metadata when set.
if [[ -z "$REGION" || -z "$ZONE" ]]; then
  PROJECT_META="$(gcloud compute project-info describe --format=json 2>/dev/null || true)"
  if [[ -n "$PROJECT_META" ]] && command -v jq >/dev/null 2>&1; then
    [[ -n "$REGION" ]] || REGION="$(jq -r '.commonInstanceMetadata.items[]? | select(.key=="google-compute-default-region") | .value' <<<"$PROJECT_META" | head -n1)"
    [[ -n "$ZONE" ]]   || ZONE="$(jq -r '.commonInstanceMetadata.items[]? | select(.key=="google-compute-default-zone") | .value' <<<"$PROJECT_META" | head -n1)"
  fi
fi

if [[ -z "$REGION" && -n "$ZONE" ]]; then
  REGION="${ZONE%-*}"
fi

# Last fallback: derive a regional location from the provisioned Spanner config.
if [[ -z "$REGION" ]]; then
  SPANNER_CONFIG="$(gcloud spanner instances describe "$INSTANCE_ID" --format='value(config)' 2>/dev/null || true)"
  SPANNER_CONFIG="${SPANNER_CONFIG##*/}"
  if [[ "$SPANNER_CONFIG" == regional-* ]]; then
    REGION="${SPANNER_CONFIG#regional-}"
  fi
fi

[[ -n "$REGION" ]] || die "Region lab tidak bisa dideteksi otomatis. Set dulu: gcloud config set compute/region REGION"

BUCKET="gs://${PROJECT_ID}"
TMP_PATH="${BUCKET}/tmp"

printf "\nProject : %s\nRegion  : %s\n" "$PROJECT_ID" "$REGION"
[[ -n "$ZONE" ]] && printf "Zone    : %s\n" "$ZONE"

# Install the Python client library in parallel with Task 2 if Cloud Shell does
# not already have it. This is only dependency preparation, not a later lab task.
PIP_PID=""
if ! python3 -c 'from google.cloud import spanner' >/dev/null 2>&1; then
  warn "google-cloud-spanner belum tersedia; instalasi dependency dimulai di background."
  (python3 -m pip install --user -q google-cloud-spanner > /tmp/gsp1049-pip.log 2>&1) &
  PIP_PID=$!
fi

# -----------------------------------------------------------------------------
# Task 1 - Explore / validate provisioned resources
# -----------------------------------------------------------------------------
say "TASK 1 — Validasi resource yang sudah disediakan lab"
gcloud spanner instances describe "$INSTANCE_ID" --format='value(name)' >/dev/null
gcloud spanner databases describe "$DATABASE_ID" --instance="$INSTANCE_ID" --format='value(name)' >/dev/null

gcloud spanner databases execute-sql "$DATABASE_ID" \
  --instance="$INSTANCE_ID" \
  --sql="SELECT COUNT(*) AS CustomerCount FROM Customer"
ok "banking-instance / banking-db / Customer terdeteksi."

# -----------------------------------------------------------------------------
# Task 2 - Insert data with DML
# -----------------------------------------------------------------------------
say "TASK 2 — Insert data with DML"
DML_ID='bdaaaa97-1b4b-4e58-b4ad-84030de92235'
if row_exists "$DML_ID"; then
  warn "Row Task 2 sudah ada; insert dilewati agar script aman dijalankan ulang."
else
  gcloud spanner databases execute-sql "$DATABASE_ID" \
    --instance="$INSTANCE_ID" \
    --sql="INSERT INTO Customer (CustomerId, Name, Location) VALUES ('$DML_ID', 'Richard Nelson', 'Ada Ohio')"
fi
row_exists "$DML_ID" || die "Verifikasi Task 2 gagal: row Richard Nelson tidak ditemukan."
ok "Row DML Richard Nelson ditemukan."
# Task 2 has no explicit Check-my-progress checkpoint in the supplied lab text.

# -----------------------------------------------------------------------------
# Task 3 - Insert data through a Python client library
# -----------------------------------------------------------------------------
say "TASK 3 — Insert data through a client library"
if [[ -n "$PIP_PID" ]]; then
  if ! wait "$PIP_PID"; then
    cat /tmp/gsp1049-pip.log >&2 || true
    die "Instalasi google-cloud-spanner gagal."
  fi
fi
python3 -c 'from google.cloud import spanner' >/dev/null 2>&1 || die "Python package google-cloud-spanner tidak tersedia."

cat > insert.py <<'PY'
from google.cloud import spanner

INSTANCE_ID = "banking-instance"
DATABASE_ID = "banking-db"

spanner_client = spanner.Client()
instance = spanner_client.instance(INSTANCE_ID)
database = instance.database(DATABASE_ID)

def insert_customer(transaction):
    row_ct = transaction.execute_update(
        "INSERT INTO Customer (CustomerId, Name, Location) "
        "VALUES ('b2b4002d-7813-4551-b83b-366ef95f9273', 'Shana Underwood', 'Ely Iowa')"
    )
    print(f"{row_ct} record(s) inserted.")

database.run_in_transaction(insert_customer)
PY

CLIENT_ID='b2b4002d-7813-4551-b83b-366ef95f9273'
if row_exists "$CLIENT_ID"; then
  warn "Row Task 3 sudah ada; insert Python dilewati."
else
  python3 insert.py
fi
row_exists "$CLIENT_ID" || die "Verifikasi Task 3 gagal: row Shana Underwood tidak ditemukan."
ok "Row Python client Shana Underwood ditemukan."
checkpoint "Insert data through a client library"

# -----------------------------------------------------------------------------
# Task 4 - Batch insert through Python client library
# -----------------------------------------------------------------------------
say "TASK 4 — Insert batch data through a client library"
BATCH_IDS=(
  'edfc683f-bd87-4bab-9423-01d1b2307c0d'
  '1f3842ca-4529-40ff-acdd-88e8a87eb404'
  '3320d98e-6437-4515-9e83-137f105f7fbc'
  '6b2b2774-add9-4881-8702-d179af0518d8'
)

BATCH_PRESENT=0
for id in "${BATCH_IDS[@]}"; do
  row_exists "$id" && ((BATCH_PRESENT+=1)) || true
done

if (( BATCH_PRESENT == 4 )); then
  warn "Semua row Task 4 sudah ada; batch insert dilewati."
else
  # If a previous interrupted run inserted only part of the batch, reset only
  # these four lab rows so the exact batch.insert() can succeed cleanly.
  if (( BATCH_PRESENT > 0 )); then
    warn "Ditemukan batch parsial; membersihkan 4 ID Task 4 lalu mengulang batch insert."
    gcloud spanner databases execute-sql "$DATABASE_ID" \
      --instance="$INSTANCE_ID" \
      --sql="DELETE FROM Customer WHERE CustomerId IN UNNEST(['${BATCH_IDS[0]}','${BATCH_IDS[1]}','${BATCH_IDS[2]}','${BATCH_IDS[3]}'])"
  fi

  cat > batch_insert.py <<'PY'
from google.cloud import spanner

INSTANCE_ID = "banking-instance"
DATABASE_ID = "banking-db"

spanner_client = spanner.Client()
instance = spanner_client.instance(INSTANCE_ID)
database = instance.database(DATABASE_ID)

with database.batch() as batch:
    batch.insert(
        table="Customer",
        columns=("CustomerId", "Name", "Location"),
        values=[
            ('edfc683f-bd87-4bab-9423-01d1b2307c0d', 'John Elkins', 'Roy Utah'),
            ('1f3842ca-4529-40ff-acdd-88e8a87eb404', 'Martin Madrid', 'Ames Iowa'),
            ('3320d98e-6437-4515-9e83-137f105f7fbc', 'Theresa Henderson', 'Anna Texas'),
            ('6b2b2774-add9-4881-8702-d179af0518d8', 'Norma Carter', 'Bend Oregon'),
        ],
    )

print("Rows inserted")
PY
  python3 batch_insert.py
fi

for id in "${BATCH_IDS[@]}"; do
  row_exists "$id" || die "Verifikasi Task 4 gagal untuk CustomerId $id"
done
ok "Keempat row batch ditemukan."
checkpoint "Insert batch data through a client library"

# -----------------------------------------------------------------------------
# Task 5 - Load data using Dataflow
# -----------------------------------------------------------------------------
say "TASK 5 — Load data using Dataflow"

# Dataflow workers need Compute Engine. On fresh lab projects the Compute Engine
# default service account might not exist until compute.googleapis.com is enabled.
gcloud services enable compute.googleapis.com dataflow.googleapis.com iam.googleapis.com --quiet

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
DEFAULT_WORKER_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
WORKER_SA=""

# Prefer the Compute Engine default service account, which is what Dataflow uses
# implicitly when --service-account-email is omitted. Give Google a few seconds
# to create it immediately after enabling Compute Engine on a fresh project.
for _ in {1..12}; do
  if gcloud iam service-accounts describe "$DEFAULT_WORKER_SA" --project="$PROJECT_ID" >/dev/null 2>&1; then
    WORKER_SA="$DEFAULT_WORKER_SA"
    break
  fi
  sleep 1
done

# If the default Compute service account is still unavailable, use an enabled
# user-managed service account if the lab already provisioned one.
if [[ -z "$WORKER_SA" ]]; then
  WORKER_SA="$(gcloud iam service-accounts list --project="$PROJECT_ID" \
    --filter='disabled:false' --format='value(email)' 2>/dev/null \
    | grep -Ev 'gcp-sa-|cloudservices\.gserviceaccount\.com$' \
    | head -n1 || true)"
fi

# Final fallback for fresh projects: create a dedicated worker service account.
if [[ -z "$WORKER_SA" ]]; then
  WORKER_SA="gsp1049-dataflow-worker@${PROJECT_ID}.iam.gserviceaccount.com"
  warn "Worker service account belum tersedia; membuat gsp1049-dataflow-worker."
  gcloud iam service-accounts create gsp1049-dataflow-worker \
    --project="$PROJECT_ID" \
    --display-name="GSP1049 Dataflow Worker" \
    --quiet
fi

# Re-enable the selected account if it exists but is disabled.
SA_DISABLED="$(gcloud iam service-accounts describe "$WORKER_SA" \
  --project="$PROJECT_ID" --format='value(disabled)' 2>/dev/null || true)"
if [[ "$SA_DISABLED" == "True" || "$SA_DISABLED" == "true" ]]; then
  warn "Worker service account disabled; mengaktifkannya."
  gcloud iam service-accounts enable "$WORKER_SA" --project="$PROJECT_ID" --quiet
fi

ok "Dataflow worker SA: $WORKER_SA"

# Ensure a dedicated/fresh worker account has the permissions needed by this
# pipeline. These grants are idempotent. Some lab projects already grant broader
# permissions; repeated bindings are harmless.
for ROLE in roles/dataflow.worker roles/storage.objectAdmin roles/spanner.databaseUser; do
  if ! gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${WORKER_SA}" \
      --role="$ROLE" --condition=None --quiet >/dev/null 2>&1; then
    warn "Tidak dapat menambah $ROLE (mungkin lab sudah mengaturnya atau IAM dibatasi)."
  fi
done

# The caller must be allowed to attach/actAs the worker service account.
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"
if [[ -n "$ACTIVE_ACCOUNT" ]]; then
  if [[ "$ACTIVE_ACCOUNT" == *.gserviceaccount.com ]]; then
    CALLER_MEMBER="serviceAccount:${ACTIVE_ACCOUNT}"
  else
    CALLER_MEMBER="user:${ACTIVE_ACCOUNT}"
  fi
  if ! gcloud iam service-accounts add-iam-policy-binding "$WORKER_SA" \
      --project="$PROJECT_ID" \
      --member="$CALLER_MEMBER" \
      --role="roles/iam.serviceAccountUser" --quiet >/dev/null 2>&1; then
    warn "Tidak dapat menambah Service Account User; lanjut karena lab mungkin sudah memberi iam.serviceAccounts.actAs."
  fi
fi

# Create the lab bucket only if it doesn't already exist.
if gcloud storage buckets describe "$BUCKET" >/dev/null 2>&1; then
  warn "$BUCKET sudah ada."
else
  gcloud storage buckets create "$BUCKET" --location="$REGION" --quiet
fi

touch emptyfile
gcloud storage cp emptyfile "${TMP_PATH}/emptyfile" --quiet

# Reuse a running/succeeded job when resuming.
EXISTING_JOB_ID="$(gcloud dataflow jobs list --region="$REGION" \
  --filter="name=$DATAFLOW_JOB" --sort-by='~createTime' --limit=1 \
  --format='value(id)' 2>/dev/null || true)"
EXISTING_STATE=""
if [[ -n "$EXISTING_JOB_ID" ]]; then
  EXISTING_STATE="$(gcloud dataflow jobs describe "$EXISTING_JOB_ID" \
    --region="$REGION" --format='value(currentState)' 2>/dev/null || true)"
fi

case "$EXISTING_STATE" in
  JOB_STATE_RUNNING|JOB_STATE_PENDING|JOB_STATE_QUEUED|JOB_STATE_DRAINING|JOB_STATE_DONE)
    warn "Dataflow job existing ditemukan: $EXISTING_STATE. Tidak membuat job duplikat."
    ;;
  *)
    gcloud dataflow jobs run "$DATAFLOW_JOB" \
      --gcs-location="gs://dataflow-templates-${REGION}/latest/GCS_Text_to_Cloud_Spanner" \
      --region="$REGION" \
      --staging-location="${TMP_PATH}" \
      --worker-machine-type="e2-medium" \
      --service-account-email="$WORKER_SA" \
      --parameters="instanceId=${INSTANCE_ID},databaseId=${DATABASE_ID},importManifest=${MANIFEST}" \
      --quiet
    ;;
esac

# Wait until the job reaches a terminal state. This prevents asking the user to
# check the objective while Dataflow is still provisioning workers.
say "Menunggu Dataflow selesai"
while true; do
  JOB_ID="$(gcloud dataflow jobs list --region="$REGION" \
    --filter="name=$DATAFLOW_JOB" --sort-by='~createTime' --limit=1 \
    --format='value(id)' 2>/dev/null || true)"
  [[ -n "$JOB_ID" ]] || { sleep 2; continue; }

  JOB_STATE="$(gcloud dataflow jobs describe "$JOB_ID" --region="$REGION" \
    --format='value(currentState)' 2>/dev/null || true)"
  printf '\rDataflow status: %-28s' "$JOB_STATE"

  case "$JOB_STATE" in
    JOB_STATE_DONE)
      printf '\n'
      ok "Dataflow selesai: JOB_STATE_DONE"
      break
      ;;
    JOB_STATE_FAILED|JOB_STATE_CANCELLED|JOB_STATE_DRAINED|JOB_STATE_UPDATED)
      printf '\n'
      die "Dataflow berhenti dengan state $JOB_STATE."
      ;;
  esac
  sleep 5
done

checkpoint "Load data using Dataflow"

say "Validasi jumlah row setelah Dataflow"
gcloud spanner databases execute-sql "$DATABASE_ID" \
  --instance="$INSTANCE_ID" \
  --sql="SELECT COUNT(*) AS CustomerCount FROM Customer"

# -----------------------------------------------------------------------------
# Task 6 - Backup database
# -----------------------------------------------------------------------------
say "TASK 6 — Backup your database"
if gcloud spanner backups describe "$BACKUP_NAME" --instance="$INSTANCE_ID" >/dev/null 2>&1; then
  warn "Backup $BACKUP_NAME sudah ada; create dilewati."
else
  gcloud spanner backups create "$BACKUP_NAME" \
    --instance="$INSTANCE_ID" \
    --database="$DATABASE_ID" \
    --retention-period=31536000s \
    --encryption-type=USE_CONFIG_DEFAULT_OR_BACKUP_ENCRYPTION \
    --async \
    --quiet
fi

gcloud spanner backups describe "$BACKUP_NAME" \
  --instance="$INSTANCE_ID" \
  --format='table(name.basename():label=BACKUP,state,createTime,expireTime)'

printf "\nBackup dibuat async agar tidak membuang waktu terminal. Lab menyatakan proses backup dapat terus berjalan sampai state READY.\n"
printf "\n${C_GREEN}============================================================${C_RESET}\n"
printf "${C_GREEN}GSP1049 selesai — semua checkpoint objective sudah kamu konfirmasi HIJAU.${C_RESET}\n"
printf "${C_GREEN}============================================================${C_RESET}\n"
