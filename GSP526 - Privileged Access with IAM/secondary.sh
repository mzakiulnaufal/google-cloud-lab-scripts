#!/usr/bin/env bash
set -Eeuo pipefail

SECONDARY_USER="student-02-5434ff13e427@qwiklabs.net"
ENTITLEMENT="pam-entitlement"
LOCATION="global"

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

if [[ "$ACTIVE_ACCOUNT" != "$SECONDARY_USER" ]]; then
  echo "ERROR: active account must be $SECONDARY_USER"
  echo "Current: $ACTIVE_ACCOUNT"
  exit 1
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "ERROR: project ID not detected"
  exit 1
fi

gcloud config set project "$PROJECT_ID" --quiet

echo "== TASK 4B: FIND PENDING GRANT =="
GRANT_NAME="$(gcloud pam grants search \
  --entitlement="$ENTITLEMENT" \
  --caller-relationship="can-approve" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --filter='state=APPROVAL_AWAITED' \
  --sort-by='~createTime' \
  --limit=1 \
  --format='value(name)')"

if [[ -z "$GRANT_NAME" ]]; then
  echo "ERROR: no pending approval grant found"
  gcloud pam grants search \
    --entitlement="$ENTITLEMENT" \
    --caller-relationship="can-approve" \
    --project="$PROJECT_ID" \
    --location="$LOCATION" || true
  exit 1
fi

echo "Grant: $GRANT_NAME"

echo
echo "== APPROVE GRANT =="
gcloud pam grants approve "$GRANT_NAME" --reason="Approved by Cymbal Security Lead for GSP526"

for ATTEMPT in $(seq 1 40); do
  STATE="$(gcloud pam grants describe "$GRANT_NAME" --format='value(state)')"
  echo "Grant state: $STATE"
  [[ "$STATE" == "ACTIVE" ]] && break
  case "$STATE" in
    ACTIVATION_FAILED|DENIED|EXPIRED|ENDED|REVOKED)
      echo "ERROR: unexpected grant state: $STATE"
      exit 1
      ;;
  esac
  sleep 5
done

if [[ "$STATE" != "ACTIVE" ]]; then
  echo "ERROR: grant did not become ACTIVE"
  exit 1
fi

echo
echo "TASK 4: click Check my progress."
read -rp "Press ENTER after Task 4 is green..."

echo
echo "== TASK 5: REVOKE GRANT =="
gcloud pam grants revoke "$GRANT_NAME" --reason="GSP526 completed; restoring least privilege"

for ATTEMPT in $(seq 1 40); do
  STATE="$(gcloud pam grants describe "$GRANT_NAME" --format='value(state)')"
  echo "Grant state: $STATE"
  [[ "$STATE" == "REVOKED" ]] && break
  sleep 5
done

if [[ "$STATE" != "REVOKED" ]]; then
  echo "ERROR: grant did not become REVOKED"
  exit 1
fi

echo
echo "TASK 5: click Check my progress."
echo "After Task 5 is green, return to the primary-user Cloud Shell and run cleanup.sh."
