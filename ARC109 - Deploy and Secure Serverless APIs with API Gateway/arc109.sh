#!/usr/bin/env bash
set -Eeuo pipefail

# ARC109 - Deploy and Secure Serverless APIs with API Gateway
# Speedrun + grader-safe checkpoints + resumable existing-resource handling.

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

WAIT_FOR_GRADER="${WAIT_FOR_GRADER:-1}"   # 1 = pause at each Check my progress objective
START_TASK="${START_TASK:-1}"             # 1, 2, or 3

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "ERROR: PROJECT_ID tidak terdeteksi. Jalankan dari Cloud Shell lab." >&2
  exit 1
fi
export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

checkpoint() {
  local task="$1"
  local objective="$2"
  [[ "$WAIT_FOR_GRADER" == "1" ]] || return 0
  echo
  echo "============================================================"
  echo " TASK $task SIAP DICEK"
  echo " $objective"
  echo "============================================================"
  echo ">>> Klik Check my progress di halaman lab."
  echo ">>> Pastikan objective TASK $task HIJAU."
  read -rp "Kalau sudah HIJAU, tekan ENTER untuk lanjut... " _
  echo
}

# Prefer the location of an already-existing gcfunction service. Otherwise use
# Qwiklabs/Skills Boost project metadata, gcloud config, then zone-derived region.
detect_region() {
  local region="" zone="" meta="{}"

  region="$(
    gcloud run services list --platform=managed --project="$PROJECT_ID" --format=json 2>/dev/null \
      | jq -r '.[] | select(.metadata.name=="gcfunction") | .metadata.labels["cloud.googleapis.com/location"] // empty' \
      | head -n1
  )"

  if [[ -z "$region" ]]; then
    meta="$(gcloud compute project-info describe --project="$PROJECT_ID" --format=json 2>/dev/null || echo '{}')"
    region="$(jq -r '.commonInstanceMetadata.items[]? | select(.key=="google-compute-default-region") | .value' <<<"$meta" | head -n1)"
    zone="$(jq -r '.commonInstanceMetadata.items[]? | select(.key=="google-compute-default-zone") | .value' <<<"$meta" | head -n1)"
  fi

  if [[ -z "$region" || "$region" == "null" || "$region" == "(unset)" ]]; then
    region="$(gcloud config get-value compute/region 2>/dev/null || true)"
  fi

  if [[ -z "$zone" || "$zone" == "null" || "$zone" == "(unset)" ]]; then
    zone="$(gcloud config get-value compute/zone 2>/dev/null || true)"
  fi

  if [[ -z "$region" || "$region" == "null" || "$region" == "(unset)" ]]; then
    if [[ -n "$zone" && "$zone" != "null" && "$zone" != "(unset)" ]]; then
      region="${zone%-*}"
    fi
  fi

  if [[ -z "$region" || "$region" == "null" || "$region" == "(unset)" ]]; then
    read -rp "REGION lab (contoh us-central1): " region
  fi

  printf '%s' "$region"
}

REGION="${REGION:-$(detect_region)}"
WORKDIR="${WORKDIR:-$HOME/arc109}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "============================================================"
echo " ARC109 SPEEDRUN"
echo "============================================================"
echo "PROJECT_ID     : $PROJECT_ID"
echo "PROJECT_NUMBER : $PROJECT_NUMBER"
echo "REGION         : $REGION"
echo "START_TASK     : $START_TASK"
echo "============================================================"

# -----------------------------------------------------------------------------
# TASK 1 - Create a Cloud Run function
# -----------------------------------------------------------------------------
if (( START_TASK <= 1 )); then
  echo
  echo "=== TASK 1: Create a Cloud Run function ==="

  cat > package.json <<'EOF'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

  cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('helloHttp', (req, res) => {
  res.status(200).send('Hello World!');
});
EOF

  # A prior/community script can create a Cloud Functions resource whose
  # underlying Cloud Run service normalizes to "gcfunction". Creating another
  # function with a differently-cased resource name can then return HTTP 409.
  # Reuse an existing service instead of destroying a grader-green Task 1.
  if gcloud run services describe gcfunction --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "✓ Existing Cloud Run service gcfunction detected; skipping duplicate deploy."
  else
    echo "Deploying gcfunction (2nd gen, Node.js 22)..."
    gcloud functions deploy gcfunction \
      --gen2 \
      --runtime=nodejs22 \
      --region="$REGION" \
      --source=. \
      --entry-point=helloHttp \
      --trigger-http \
      --allow-unauthenticated \
      --project="$PROJECT_ID" \
      --quiet
  fi

  checkpoint "1" "Create a Cloud Run function"
fi

# Need existing backend for Task 2/3.
if ! gcloud run services describe gcfunction --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "ERROR: gcfunction tidak ditemukan di region $REGION." >&2
  echo "Jalankan START_TASK=1 atau pastikan region lab benar." >&2
  exit 1
fi

FUNCTION_URL="$(
  gcloud run services describe gcfunction \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(status.url)'
)"
[[ -n "$FUNCTION_URL" ]] || FUNCTION_URL="https://gcfunction-${PROJECT_NUMBER}.${REGION}.run.app"

API_ID="gcfunction-api"
CONFIG_ID="gcfunction-api"
GATEWAY_ID="gcfunction-api"

# -----------------------------------------------------------------------------
# TASK 2 - Create an API Gateway
# -----------------------------------------------------------------------------
if (( START_TASK <= 2 )); then
  echo
  echo "=== TASK 2: Create an API Gateway ==="

  # Batch enable; commands are idempotent. Cloud Run APIs are pre-enabled by lab.
  gcloud services enable \
    apigateway.googleapis.com \
    servicemanagement.googleapis.com \
    servicecontrol.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

  cat > openapispec.yaml <<EOF
swagger: '2.0'
info:
  title: gcfunction API
  description: Sample API on API Gateway with a Google Cloud Run functions backend
  version: 1.0.0
schemes:
- https
produces:
- application/json
x-google-backend:
  address: ${FUNCTION_URL}
paths:
  /gcfunction:
    get:
      summary: gcfunction
      operationId: gcfunction
      responses:
        '200':
          description: A successful response
          schema:
            type: string
EOF

  if ! gcloud api-gateway apis describe "$API_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud api-gateway apis create "$API_ID" \
      --display-name="gcfunction API" \
      --project="$PROJECT_ID" \
      --quiet
  else
    echo "✓ API $API_ID already exists."
  fi

  if ! gcloud api-gateway api-configs describe "$CONFIG_ID" \
      --api="$API_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "Creating API config (this is one of the slow lab operations)..."
    gcloud api-gateway api-configs create "$CONFIG_ID" \
      --api="$API_ID" \
      --display-name="gcfunction API" \
      --openapi-spec=openapispec.yaml \
      --backend-auth-service-account="$COMPUTE_SA" \
      --project="$PROJECT_ID" \
      --quiet
  else
    echo "✓ API config $CONFIG_ID already exists under $API_ID."
  fi

  if ! gcloud api-gateway gateways describe "$GATEWAY_ID" \
      --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "Creating gateway (main ARC109 time bottleneck)..."
    gcloud api-gateway gateways create "$GATEWAY_ID" \
      --api="$API_ID" \
      --api-config="$CONFIG_ID" \
      --location="$REGION" \
      --display-name="gcfunction API" \
      --project="$PROJECT_ID" \
      --quiet
  else
    CURRENT_CONFIG="$(
      gcloud api-gateway gateways describe "$GATEWAY_ID" \
        --location="$REGION" --project="$PROJECT_ID" \
        --format='value(apiConfig)' 2>/dev/null || true
    )"
    if [[ "$CURRENT_CONFIG" != *"/apis/${API_ID}/configs/${CONFIG_ID}" ]]; then
      echo "Existing gateway points to another API/config; correcting it..."
      gcloud api-gateway gateways update "$GATEWAY_ID" \
        --api="$API_ID" \
        --api-config="$CONFIG_ID" \
        --location="$REGION" \
        --display-name="gcfunction API" \
        --project="$PROJECT_ID" \
        --quiet
    else
      echo "✓ Gateway $GATEWAY_ID already uses the correct config."
    fi
  fi

  GATEWAY_HOST="$(
    gcloud api-gateway gateways describe "$GATEWAY_ID" \
      --location="$REGION" --project="$PROJECT_ID" \
      --format='value(defaultHostname)'
  )"
  echo "Gateway endpoint: https://${GATEWAY_HOST}/gcfunction"

  checkpoint "2" "Create an API Gateway"
fi

# -----------------------------------------------------------------------------
# TASK 3 - Pub/Sub topic + update function + invoke through gateway
# -----------------------------------------------------------------------------
if (( START_TASK <= 3 )); then
  echo
  echo "=== TASK 3: Pub/Sub + API backend ==="

  gcloud services enable pubsub.googleapis.com --project="$PROJECT_ID" --quiet

  if ! gcloud pubsub topics describe demo-topic --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud pubsub topics create demo-topic --project="$PROJECT_ID" --quiet
  else
    echo "✓ demo-topic already exists."
  fi

  # Matches Console's "Add a default subscription" behavior.
  if ! gcloud pubsub subscriptions describe demo-topic-sub --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud pubsub subscriptions create demo-topic-sub \
      --topic=demo-topic \
      --project="$PROJECT_ID" \
      --quiet
  else
    echo "✓ demo-topic-sub already exists."
  fi

  RUNTIME_SA="$(
    gcloud run services describe gcfunction \
      --region="$REGION" --project="$PROJECT_ID" \
      --format='value(spec.template.spec.serviceAccountName)' 2>/dev/null || true
  )"
  [[ -n "$RUNTIME_SA" ]] || RUNTIME_SA="$COMPUTE_SA"

  gcloud pubsub topics add-iam-policy-binding demo-topic \
    --member="serviceAccount:${RUNTIME_SA}" \
    --role="roles/pubsub.publisher" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null

  cat > package.json <<'EOF'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^3.4.1"
  }
}
EOF

  cat > index.js <<'EOF'
const {PubSub} = require('@google-cloud/pubsub');
const functions = require('@google-cloud/functions-framework');

const pubsub = new PubSub();
const topic = pubsub.topic('demo-topic');

functions.http('helloHttp', async (req, res) => {
  try {
    await topic.publishMessage({
      data: Buffer.from('Hello from Cloud Run functions!')
    });
    res.status(200).send('Message sent to Topic demo-topic!');
  } catch (err) {
    console.error(err);
    res.status(500).send(err.message);
  }
});
EOF

  # Deliberately update the existing Cloud Run service rather than trying to
  # create a new Cloud Functions resource. This avoids the observed 409:
  # "A Cloud Run service with this name already exists".
  echo "Updating existing gcfunction with Pub/Sub publishing code..."
  gcloud run deploy gcfunction \
    --source=. \
    --function=helloHttp \
    --base-image=nodejs22 \
    --region="$REGION" \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

  GATEWAY_HOST="$(
    gcloud api-gateway gateways describe "$GATEWAY_ID" \
      --location="$REGION" --project="$PROJECT_ID" \
      --format='value(defaultHostname)'
  )"
  if [[ -z "$GATEWAY_HOST" ]]; then
    echo "ERROR: Gateway gcfunction-api tidak ditemukan/siap di $REGION." >&2
    exit 1
  fi

  ENDPOINT="https://${GATEWAY_HOST}/gcfunction"
  echo "Invoking through API Gateway: $ENDPOINT"

  RESPONSE="$(curl -fsS --retry 6 --retry-delay 2 --retry-all-errors "$ENDPOINT")"
  echo "Response: $RESPONSE"

  if [[ "$RESPONSE" != *"Message sent to Topic demo-topic!"* ]]; then
    echo "ERROR: Unexpected API response; Pub/Sub publish could not be confirmed." >&2
    exit 1
  fi

  checkpoint "3" "Create a Pub/Sub Topic and Publish Messages via API Backend"
fi

echo
echo "============================================================"
echo " ARC109 COMPLETE"
echo "============================================================"
echo "Project      : $PROJECT_ID"
echo "Region       : $REGION"
echo "Function     : gcfunction"
echo "API          : gcfunction-api"
echo "API Config   : gcfunction-api"
echo "Gateway      : gcfunction-api"
echo "Topic        : demo-topic"
echo "Subscription : demo-topic-sub"
if GATEWAY_HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" --location="$REGION" --project="$PROJECT_ID" --format='value(defaultHostname)' 2>/dev/null)" && [[ -n "$GATEWAY_HOST" ]]; then
  echo "Endpoint     : https://${GATEWAY_HOST}/gcfunction"
fi
echo "============================================================"
