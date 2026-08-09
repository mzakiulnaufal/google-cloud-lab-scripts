#!/usr/bin/env bash
set -euo pipefail

INSTANCE="banking-ops-instance"
DATABASE="banking-ops-db"
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || {
  echo "[ERROR] PROJECT_ID tidak terdeteksi." >&2
  exit 1
}

echo "==> Recovery - Task 6: Add MarketingBudget INT64"
gcloud spanner databases ddl update "$DATABASE" \
  --instance="$INSTANCE" \
  --project="$PROJECT_ID" \
  --ddl='ALTER TABLE Category ADD COLUMN IF NOT EXISTS MarketingBudget INT64;' \
  --quiet

echo "[OK] MarketingBudget ready"
echo ">>> CHECK MY PROGRESS: Add Column"
