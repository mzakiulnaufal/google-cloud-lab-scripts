#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GSP1048 - Cloud Spanner: Database Fundamentals
# Speedrun + reusable Cloud Shell script
# - Auto-detect PROJECT_ID / REGION / Spanner config
# - Parallel provisioning for banking-instance + banking-instance-2
# - Resumable/idempotent where practical
# - Pauses only at grader "Check my progress" checkpoints
# - Prepares Terraform in background to reduce wall-clock time
# ============================================================

export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export PATH="$HOME/bin:$PATH"

INST1="banking-instance"
DB1="banking-db"
INST2="banking-instance-2"
DB2="banking-db-2"
INST3="banking-instance-3"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

checkpoint() {
  local msg="$1"
  printf '\n\033[1;33m============================================================\033[0m\n'
  printf '\033[1;33mCHECK MY PROGRESS: %s\033[0m\n' "$msg"
  printf '\033[1;33mClick Check my progress in Skills Boost. When it is GREEN, press ENTER.\033[0m\n'
  printf '\033[1;33m============================================================\033[0m\n'
  read -r
}

# ---------- Project detection ----------
PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-}}"
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die "PROJECT_ID could not be detected."
gcloud config set project "$PROJECT_ID" >/dev/null
ok "PROJECT_ID=$PROJECT_ID"

# ---------- Region / Spanner config detection ----------
REGION="${REGION:-${CLOUDSDK_COMPUTE_REGION:-}}"
ZONE="${ZONE:-${CLOUDSDK_COMPUTE_ZONE:-}}"
SPANNER_CONFIG="${SPANNER_CONFIG:-}"

# 1) Project metadata (preferred in Skills Boost labs)
if [[ -z "$REGION" || -z "$ZONE" ]]; then
  META_JSON="$(gcloud compute project-info describe --project="$PROJECT_ID" --format=json 2>/dev/null || true)"
  if command -v jq >/dev/null 2>&1 && [[ -n "$META_JSON" ]]; then
    [[ -n "$REGION" ]] || REGION="$(
      jq -r '.commonInstanceMetadata.items[]? |
        select(.key=="google-compute-default-region") | .value' <<<"$META_JSON" | head -n1
    )"
    [[ -n "$ZONE" ]] || ZONE="$(
      jq -r '.commonInstanceMetadata.items[]? |
        select(.key=="google-compute-default-zone") | .value' <<<"$META_JSON" | head -n1
    )"
  fi
fi

# 2) gcloud local defaults
if [[ -z "$REGION" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
  [[ "$REGION" == "(unset)" ]] && REGION=""
fi
if [[ -z "$ZONE" ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
  [[ "$ZONE" == "(unset)" ]] && ZONE=""
fi

# 3) Derive region from zone if necessary
if [[ -z "$REGION" && -n "$ZONE" ]]; then
  REGION="${ZONE%-*}"
fi

# 4) Allow explicit SPANNER_CONFIG override, otherwise regional-$REGION
if [[ -n "$SPANNER_CONFIG" && -z "$REGION" ]]; then
  REGION="${SPANNER_CONFIG#regional-}"
fi
if [[ -z "$SPANNER_CONFIG" && -n "$REGION" ]]; then
  SPANNER_CONFIG="regional-$REGION"
fi

[[ -n "$SPANNER_CONFIG" ]] || die \
  "Lab region could not be detected. Re-run with: REGION=<lab-region> $0"

# Verify the detected Spanner configuration exists.
# If Spanner API is not enabled yet, enable it only on the failure path.
if ! gcloud spanner instance-configs describe "$SPANNER_CONFIG" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  warn "Spanner config could not be verified; enabling the Spanner API and retrying..."
  gcloud services enable spanner.googleapis.com --project="$PROJECT_ID" --quiet >/dev/null
  gcloud spanner instance-configs describe "$SPANNER_CONFIG" \
    --project="$PROJECT_ID" >/dev/null 2>&1 || \
    die "Spanner config '$SPANNER_CONFIG' is unavailable. Check the lab region, then run: REGION=<lab-region> $0"
fi

ok "REGION=$REGION"
ok "SPANNER_CONFIG=$SPANNER_CONFIG"

# ---------- Helpers ----------
instance_exists() {
  gcloud spanner instances describe "$1" --project="$PROJECT_ID" >/dev/null 2>&1
}
database_exists() {
  gcloud spanner databases describe "$2" \
    --instance="$1" --project="$PROJECT_ID" >/dev/null 2>&1
}

create_instance() {
  local id="$1" desc="$2" nodes="$3"
  if instance_exists "$id"; then
    ok "$id already exists"
    return 0
  fi
  gcloud spanner instances create "$id" \
    --project="$PROJECT_ID" \
    --config="$SPANNER_CONFIG" \
    --description="$desc" \
    --edition=ENTERPRISE \
    --nodes="$nodes" \
    --quiet
  ok "$id created"
}

create_database() {
  local inst="$1" db="$2"
  if database_exists "$inst" "$db"; then
    ok "$db already exists"
    return 0
  fi
  gcloud spanner databases create "$db" \
    --instance="$inst" \
    --project="$PROJECT_ID" \
    --quiet
  ok "$db created"
}

# ---------- Terraform preparation in background ----------
TF_DIR="$HOME/gsp1048-terraform"
TF_LOG="/tmp/gsp1048-terraform-prep.log"

prepare_terraform() {
  mkdir -p "$HOME/bin" "$TF_DIR"

  if ! command -v terraform >/dev/null 2>&1; then
    local tf_version="1.9.8"
    local machine arch
    machine="$(uname -m)"
    case "$machine" in
      x86_64|amd64) arch="amd64" ;;
      aarch64|arm64) arch="arm64" ;;
      *) echo "Unsupported architecture: $machine"; return 1 ;;
    esac

    curl -fsSL \
      "https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_linux_${arch}.zip" \
      -o /tmp/terraform.zip
    rm -rf /tmp/gsp1048-tf-bin
    mkdir -p /tmp/gsp1048-tf-bin
    unzip -oq /tmp/terraform.zip -d /tmp/gsp1048-tf-bin
    install -m 0755 /tmp/gsp1048-tf-bin/terraform "$HOME/bin/terraform"
  fi

  cat > "$TF_DIR/spanner.tf" <<EOF
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "google" {
  project = "$PROJECT_ID"
}

resource "google_spanner_instance" "banking_instance_3" {
  name         = "$INST3"
  config       = "$SPANNER_CONFIG"
  display_name = "Banking Instance 3"
  num_nodes    = 2
  edition      = "ENTERPRISE"
  labels       = {}
}
EOF

  terraform -chdir="$TF_DIR" init -input=false -no-color >/dev/null
}

prepare_terraform >"$TF_LOG" 2>&1 &
TF_PREP_PID=$!

# ============================================================
# TASK 1 + TASK 2
# Start Task 5's instance/database in parallel for speed.
# ============================================================
log "TASK 1-2 + pre-provision TASK 5 in parallel"

(
  create_instance "$INST1" "banking-instance" 1
  create_database "$INST1" "$DB1"
) &
PRIMARY_PID=$!

(
  # Task 5 requires 2 nodes at checker time.
  if instance_exists "$INST2"; then
    # Restore expected Task-5 state if this is a resumed run.
    gcloud spanner instances update "$INST2" \
      --project="$PROJECT_ID" --nodes=2 --quiet >/dev/null
    ok "$INST2 ready at 2 nodes"
  else
    create_instance "$INST2" "Banking Instance 2" 2
  fi
  create_database "$INST2" "$DB2"
) &
SECONDARY_PID=$!

wait "$PRIMARY_PID"
checkpoint "Task 2 — Create an instance and database"

# ============================================================
# TASK 3 - Schema
# ============================================================
log "TASK 3 — Create Customer table"

if ! gcloud spanner databases ddl describe "$DB1" \
      --instance="$INST1" --project="$PROJECT_ID" 2>/dev/null \
      | grep -qE 'CREATE TABLE[[:space:]]+Customer'; then
  gcloud spanner databases ddl update "$DB1" \
    --instance="$INST1" \
    --project="$PROJECT_ID" \
    --ddl="CREATE TABLE Customer (
      CustomerId STRING(36) NOT NULL,
      Name STRING(MAX) NOT NULL,
      Location STRING(MAX) NOT NULL,
    ) PRIMARY KEY (CustomerId);"
else
  ok "Customer table already exists"
fi

checkpoint "Task 3 — Create a schema for your database"

# ============================================================
# TASK 4 - Insert data + query
# ============================================================
log "TASK 4 — Insert data and run SELECT"

row_exists() {
  local customer_id="$1"
  gcloud spanner databases execute-sql "$DB1" \
    --instance="$INST1" \
    --project="$PROJECT_ID" \
    --sql="SELECT CustomerId FROM Customer WHERE CustomerId='$customer_id'" \
    --format='value(CustomerId)' 2>/dev/null | grep -qx "$customer_id"
}

CID1="bdaaaa97-1b4b-4e58-b4ad-84030de92235"
CID2="b2b4002d-7813-4551-b83b-366ef95f9273"

if ! row_exists "$CID1"; then
  gcloud spanner rows insert \
    --instance="$INST1" \
    --database="$DB1" \
    --table=Customer \
    --project="$PROJECT_ID" \
    --data="CustomerId=$CID1,Name=Richard Nelson,Location=Ada Ohio"
else
  ok "Richard Nelson row already exists"
fi

if ! row_exists "$CID2"; then
  gcloud spanner rows insert \
    --instance="$INST1" \
    --database="$DB1" \
    --table=Customer \
    --project="$PROJECT_ID" \
    --data="CustomerId=$CID2,Name=Shana Underwood,Location=Ely Iowa"
else
  ok "Shana Underwood row already exists"
fi

gcloud spanner databases execute-sql "$DB1" \
  --instance="$INST1" \
  --project="$PROJECT_ID" \
  --sql='SELECT * FROM Customer;' \
  --format='table(CustomerId,Name,Location)'

# ============================================================
# TASK 5 - CLI instance + database
# ============================================================
log "TASK 5 — Verify banking-instance-2 + banking-db-2"

wait "$SECONDARY_PID"

gcloud spanner instances list \
  --project="$PROJECT_ID" \
  --filter="name:($INST1 OR $INST2)" \
  --format='table(name.basename():label=INSTANCE,config.basename():label=CONFIG,nodeCount:label=NODES,edition:label=EDITION)'

checkpoint "Task 5 — Create an instance and database with CLI"

# Only resize AFTER Task 5 is green.
log "TASK 5 continuation — Reduce banking-instance-2 from 2 nodes to 1"
gcloud spanner instances update "$INST2" \
  --project="$PROJECT_ID" \
  --nodes=1 \
  --quiet
ok "$INST2 resized to 1 node"

# ============================================================
# TASK 6 - Terraform
# ============================================================
log "TASK 6 — Terraform: create banking-instance-3"

if ! wait "$TF_PREP_PID"; then
  cat "$TF_LOG" >&2 || true
  die "Terraform preparation failed."
fi

terraform version | head -n1

# Make reruns safe if the resource exists but Terraform state was lost.
if instance_exists "$INST3"; then
  if ! terraform -chdir="$TF_DIR" state show google_spanner_instance.banking_instance_3 \
       >/dev/null 2>&1; then
    terraform -chdir="$TF_DIR" import -input=false -no-color \
      google_spanner_instance.banking_instance_3 \
      "projects/$PROJECT_ID/instances/$INST3" >/dev/null
  fi
fi

# terraform apply already builds a plan internally; skip a separate plan for speed.
terraform -chdir="$TF_DIR" apply \
  -auto-approve \
  -input=false \
  -no-color

ok "$INST3 created/managed by Terraform"

# ============================================================
# TASK 7 - Delete banking-instance-2
# ============================================================
log "TASK 7 — Delete banking-instance-2"

if instance_exists "$INST2"; then
  gcloud spanner instances delete "$INST2" \
    --project="$PROJECT_ID" \
    --quiet
fi

log "FINAL STATE"
gcloud spanner instances list \
  --project="$PROJECT_ID" \
  --format='table(name.basename():label=INSTANCE,config.basename():label=CONFIG,nodeCount:label=NODES,edition:label=EDITION)'

printf '\n\033[1;32mGSP1048 complete: Tasks 1-7 executed.\033[0m\n'
