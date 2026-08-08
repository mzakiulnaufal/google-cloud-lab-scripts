#!/usr/bin/env bash
set -Eeuo pipefail

PRIMARY_USER="student-01-51ac5fa5f91a@qwiklabs.net"
SECONDARY_USER="student-02-5434ff13e427@qwiklabs.net"
ENTITLEMENT="pam-entitlement"
LOCATION="global"

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

if [[ "$ACTIVE_ACCOUNT" != "$PRIMARY_USER" ]]; then
  echo "ERROR: active account must be $PRIMARY_USER"
  echo "Current: $ACTIVE_ACCOUNT"
  exit 1
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "ERROR: project ID not detected"
  exit 1
fi

gcloud config set project "$PROJECT_ID" --quiet

echo "== TASK 1: ENABLE PAM =="
gcloud services enable privilegedaccessmanager.googleapis.com --project="$PROJECT_ID" --quiet

ORG_ID="$(gcloud projects get-ancestors "$PROJECT_ID" --format='csv[no-heading](id,type)' | awk -F',' '$2=="organization" {print $1; exit}')"
if [[ -z "$ORG_ID" ]]; then
  echo "ERROR: organization ID not found"
  exit 1
fi

PAM_SERVICE_AGENT="service-org-${ORG_ID}@gcp-sa-pam.iam.gserviceaccount.com"

gcloud pam check-onboarding-status --project="$PROJECT_ID" --location="$LOCATION" || true

for ATTEMPT in $(seq 1 20); do
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${PAM_SERVICE_AGENT}" \
      --role="roles/privilegedaccessmanager.serviceAgent" \
      --quiet >/dev/null 2>&1; then
    break
  fi
  if [[ "$ATTEMPT" == "20" ]]; then
    echo "ERROR: failed to grant PAM service-agent role"
    exit 1
  fi
  sleep 5
done

echo "PAM service agent: $PAM_SERVICE_AGENT"

echo
echo "== TASK 2: CREATE ENTITLEMENT (10 HOURS) =="
cat > "$HOME/pam-entitlement.yaml" <<YAML
privilegedAccess:
  gcpIamAccess:
    resourceType: cloudresourcemanager.googleapis.com/Project
    resource: //cloudresourcemanager.googleapis.com/projects/${PROJECT_ID}
    roleBindings:
    - role: roles/compute.admin

maxRequestDuration: 36000s

eligibleUsers:
- principals:
  - user:${PRIMARY_USER}

approvalWorkflow:
  manualApprovals:
    requireApproverJustification: false
    steps:
    - approvalsNeeded: 1
      approvers:
      - principals:
        - user:${SECONDARY_USER}

requesterJustificationConfig:
  notMandatory: {}
YAML

gcloud pam entitlements create "$ENTITLEMENT" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --entitlement-file="$HOME/pam-entitlement.yaml"

for ATTEMPT in $(seq 1 30); do
  STATE="$(gcloud pam entitlements describe "$ENTITLEMENT" --project="$PROJECT_ID" --location="$LOCATION" --format='value(state)' 2>/dev/null || true)"
  echo "Entitlement state: $STATE"
  [[ "$STATE" == "AVAILABLE" ]] && break
  sleep 5
done

if [[ "$STATE" != "AVAILABLE" ]]; then
  echo "ERROR: entitlement did not become AVAILABLE"
  exit 1
fi

echo
echo "TASK 2: click Check my progress before continuing."
read -rp "Press ENTER after Task 2 is green..."

echo
echo "== TASK 3: UPDATE MAX DURATION TO 4 HOURS =="
gcloud pam entitlements export "$ENTITLEMENT" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --destination="$HOME/pam-entitlement-update.yaml"

sed -i -E 's/^([[:space:]]*)maxRequestDuration:[[:space:]]*.*/\1maxRequestDuration: 14400s/' "$HOME/pam-entitlement-update.yaml"

gcloud pam entitlements update "$ENTITLEMENT" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --entitlement-file="$HOME/pam-entitlement-update.yaml"

for ATTEMPT in $(seq 1 30); do
  STATE="$(gcloud pam entitlements describe "$ENTITLEMENT" --project="$PROJECT_ID" --location="$LOCATION" --format='value(state)' 2>/dev/null || true)"
  echo "Entitlement state: $STATE"
  [[ "$STATE" == "AVAILABLE" ]] && break
  sleep 5
done

DURATION="$(gcloud pam entitlements describe "$ENTITLEMENT" --project="$PROJECT_ID" --location="$LOCATION" --format='value(maxRequestDuration)')"
if [[ "$DURATION" != "14400s" ]]; then
  echo "ERROR: expected 14400s, got $DURATION"
  exit 1
fi

echo
echo "TASK 3: click Check my progress before continuing."
read -rp "Press ENTER after Task 3 is green..."

echo
echo "== TASK 4A: REQUEST 4-HOUR GRANT =="
GRANT_NAME="$(gcloud pam grants create \
  --entitlement="$ENTITLEMENT" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --requested-duration="14400s" \
  --justification="GSP526 temporary Compute Admin access test" \
  --format='value(name)')"

if [[ -z "$GRANT_NAME" ]]; then
  echo "ERROR: grant creation failed"
  exit 1
fi

echo "Grant: $GRANT_NAME"
echo
echo "Switch to the secondary-user Cloud Shell and run secondary.sh."
