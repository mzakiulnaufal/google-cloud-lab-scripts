#!/usr/bin/env bash
set -Eeuo pipefail

PRIMARY_USER="student-01-51ac5fa5f91a@qwiklabs.net"
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

echo "== VERIFY GRANTS =="
gcloud pam grants list \
  --entitlement="$ENTITLEMENT" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --format='table(name.basename():label=GRANT_ID,requester,requestedDuration,state)' || true

BLOCKING_GRANTS="$(gcloud pam grants list \
  --entitlement="$ENTITLEMENT" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --filter='state=ACTIVE OR state=ACTIVATING OR state=REVOKING' \
  --format='value(name)' 2>/dev/null || true)"

if [[ -n "$BLOCKING_GRANTS" ]]; then
  echo "ERROR: active/in-progress grant still exists:"
  echo "$BLOCKING_GRANTS"
  exit 1
fi

echo
echo "== TASK 6: DELETE ENTITLEMENT =="
gcloud pam entitlements delete "$ENTITLEMENT" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --quiet

echo
echo "Remaining entitlements:"
gcloud pam entitlements list \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --format='table(name.basename():label=ENTITLEMENT,state,maxRequestDuration)' || true

echo
echo "== PAM AUDIT LOGS =="
gcloud logging read \
  'protoPayload.serviceName="privilegedaccessmanager.googleapis.com" AND protoPayload.resourceName:"pam-entitlement"' \
  --project="$PROJECT_ID" \
  --order=desc \
  --limit=100 \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail:label=PRINCIPAL,protoPayload.methodName:label=METHOD,protoPayload.resourceName:label=RESOURCE)' || true

echo
echo "Task 6 cleanup complete. Click Check my progress in the lab."
