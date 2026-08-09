#!/bin/bash
set -Eeuo pipefail

SERVICE="gcfunction"

# ============================================================
# GSP081 - Cloud Run Functions: Qwik Start - Console
# Speedrun-oriented Cloud Shell automation
# ============================================================

# ---------- PROJECT ----------
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "ERROR: PROJECT_ID could not be detected."
  exit 1
fi

gcloud config set project "$PROJECT_ID" --quiet >/dev/null

# ---------- REGION / ZONE AUTO-DETECTION ----------
REGION="$(
  gcloud compute project-info describe \
    --project="$PROJECT_ID" \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
    2>/dev/null || true
)"

ZONE="$(
  gcloud compute project-info describe \
    --project="$PROJECT_ID" \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
    2>/dev/null || true
)"

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value run/region 2>/dev/null || true)"
fi

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi

if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
fi

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  if [[ -n "$ZONE" && "$ZONE" != "(unset)" ]]; then
    REGION="${ZONE%-*}"
  fi
fi

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  echo "ERROR: Lab region could not be detected automatically."
  echo "Set it manually and rerun: export REGION=<LAB_REGION>"
  exit 1
fi

# Allow an explicit REGION override without participant hardcoding.
REGION="${REGION_OVERRIDE:-$REGION}"

echo "========================================"
echo " GSP081 SPEEDRUN"
echo " Project : $PROJECT_ID"
echo " Region  : $REGION"
echo " Service : $SERVICE"
echo "========================================"

# ---------- REQUIRED APIS ----------
echo "[1/3] Enabling required APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

# ---------- FUNCTION SOURCE ----------
echo "[2/3] Deploying Cloud Run function..."
WORKDIR="$(mktemp -d /tmp/gsp081.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

cat > package.json <<'JSON'
{
  "name": "gcfunction",
  "version": "1.0.0",
  "private": true,
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.4.0"
  }
}
JSON

cat > index.js <<'JS'
const functions = require('@google-cloud/functions-framework');

functions.http('helloHttp', (req, res) => {
  res.send(req.body?.message || 'Hello World!');
});
JS

# Current Cloud Run function deployment path: source + function entry point.
gcloud run deploy "$SERVICE" \
  --source=. \
  --function=helloHttp \
  --base-image=nodejs24 \
  --region="$REGION" \
  --execution-environment=gen2 \
  --max-instances=5 \
  --allow-unauthenticated \
  --project="$PROJECT_ID" \
  --quiet

# ---------- TEST / CREATE REQUEST LOG ----------
URL="$(
  gcloud run services describe "$SERVICE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(status.url)'
)"

if [[ -z "$URL" ]]; then
  echo "ERROR: Deployed service URL was not returned."
  exit 1
fi

echo "[3/3] Testing function..."
RESULT="$(
  curl -fsS \
    --retry 5 \
    --retry-delay 2 \
    --retry-all-errors \
    --max-time 30 \
    -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -d '{"message":"Hello World!"}'
)"

echo
echo "========================================"
echo " Response : $RESULT"
echo " URL      : $URL"
echo "========================================"

if [[ "$RESULT" != "Hello World!" ]]; then
  echo "ERROR: Function deployed, but the test response was unexpected."
  exit 1
fi

echo "✅ Deploy the function: DONE"
echo "✅ Test the function  : DONE"
echo
echo "Check both grader objectives in the lab page."
echo "Task 5 answers: True / HTTPS"
