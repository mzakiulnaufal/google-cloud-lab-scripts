#!/usr/bin/env bash
set -Eeuo pipefail

# GSP1050 - Spanner: Defining Schemas and Understanding Query Plans
# Speedrun + grader checkpoints + automatic retry for transient Spanner ABORTED errors.

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
INSTANCE="${INSTANCE:-banking-ops-instance}"
DATABASE="${DATABASE:-banking-ops-db}"
WAIT_FOR_GRADER="${WAIT_FOR_GRADER:-1}"   # 1 = pause at real Check my progress objectives
RUN_QUERY_TASKS="${RUN_QUERY_TASKS:-0}"   # 0 = fastest grader mode; 1 = also run read/query-plan exercises
MAX_SQL_RETRIES="${MAX_SQL_RETRIES:-8}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "ERROR: PROJECT_ID tidak terdeteksi. Jalankan dari Cloud Shell lab." >&2
  exit 1
fi

export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"

# Execute Spanner SQL and retry only transient ABORTED/schema-change failures.
# No fixed delay is added to successful commands.
sql() {
  local statement="$1"
  local attempt=1
  local rc out

  while (( attempt <= MAX_SQL_RETRIES )); do
    set +e
    out="$(gcloud spanner databases execute-sql "$DATABASE" \
      --instance="$INSTANCE" \
      --project="$PROJECT_ID" \
      --sql="$statement" \
      --quiet 2>&1)"
    rc=$?
    set -e

    if (( rc == 0 )); then
      [[ -n "$out" ]] && printf '%s\n' "$out"
      return 0
    fi

    if grep -Eqi 'ABORTED|Database schema has changed|schema probably changed' <<<"$out"; then
      if (( attempt == MAX_SQL_RETRIES )); then
        printf '%s\n' "$out" >&2
        echo "ERROR: SQL masih ABORTED setelah $MAX_SQL_RETRIES percobaan." >&2
        return "$rc"
      fi

      # Short backoff: 0.35s, 0.70s, 1.05s ... capped at 2s.
      local delay
      delay="$(awk -v n="$attempt" 'BEGIN { d=0.35*n; if (d>2) d=2; printf "%.2f", d }')"
      echo "    ↻ Spanner schema berubah; retry $attempt/$MAX_SQL_RETRIES dalam ${delay}s..." >&2
      sleep "$delay"
      ((attempt++))
      continue
    fi

    printf '%s\n' "$out" >&2
    return "$rc"
  done
}

plan() {
  local statement="$1"
  local attempt=1
  local rc out

  while (( attempt <= MAX_SQL_RETRIES )); do
    set +e
    out="$(gcloud spanner databases execute-sql "$DATABASE" \
      --instance="$INSTANCE" \
      --project="$PROJECT_ID" \
      --query-mode=PLAN \
      --sql="$statement" \
      --quiet 2>&1)"
    rc=$?
    set -e

    if (( rc == 0 )); then
      [[ -n "$out" ]] && printf '%s\n' "$out"
      return 0
    fi

    if grep -Eqi 'ABORTED|Database schema has changed|schema probably changed' <<<"$out"; then
      if (( attempt == MAX_SQL_RETRIES )); then
        printf '%s\n' "$out" >&2
        return "$rc"
      fi
      sleep 0.5
      ((attempt++))
      continue
    fi

    printf '%s\n' "$out" >&2
    return "$rc"
  done
}

checkpoint() {
  local task="$1"
  local objective="$2"

  [[ "$WAIT_FOR_GRADER" == "1" ]] || return 0

  echo
  echo "============================================================"
  echo "✅ $task selesai"
  echo "🎯 Objective: $objective"
  echo "👉 Klik 'Check my progress' di Skills Boost."
  echo "============================================================"
  read -r -p "Kalau objective sudah HIJAU, tekan ENTER untuk lanjut... " _
  echo
}

# Fast local prerequisite check.
echo "==> GSP1050 | project=$PROJECT_ID | instance=$INSTANCE | db=$DATABASE"
gcloud spanner databases describe "$DATABASE" \
  --instance="$INSTANCE" \
  --project="$PROJECT_ID" \
  --format='value(name)' >/dev/null

# -----------------------------------------------------------------------------
# TASK 1 - Load Portfolio, Category, Product
# Parent -> child order is required by the schema.
# -----------------------------------------------------------------------------
echo "==> TASK 1 — Load Portfolio"
sql "INSERT OR UPDATE INTO Portfolio (PortfolioId, Name, ShortName, PortfolioInfo) VALUES
  (1, 'Banking', 'Bnkg', 'All Banking Business'),
  (2, 'Asset Growth', 'AsstGrwth', 'All Asset Focused Products'),
  (3, 'Insurance', 'Ins', 'All Insurance Focused Products')"

echo "==> TASK 1 — Load Category"
sql "INSERT OR UPDATE INTO Category (CategoryId, PortfolioId, CategoryName) VALUES
  (1, 1, 'Cash'),
  (2, 2, 'Investments - Short Return'),
  (3, 2, 'Annuities'),
  (4, 3, 'Life Insurance')"

echo "==> TASK 1 — Load Product"
sql "INSERT OR UPDATE INTO Product (ProductId, CategoryId, PortfolioId, ProductName, ProductAssetCode, ProductClass) VALUES
  (1, 1, 1, 'Checking Account', 'ChkAcct', 'Banking LOB'),
  (2, 2, 2, 'Mutual Fund Consumer Goods', 'MFundCG', 'Investment LOB'),
  (3, 3, 2, 'Annuity Early Retirement', 'AnnuFixed', 'Investment LOB'),
  (4, 4, 3, 'Term Life Insurance', 'TermLife', 'Insurance LOB'),
  (5, 1, 1, 'Savings Account', 'SavAcct', 'Banking LOB'),
  (6, 1, 1, 'Personal Loan', 'PersLn', 'Banking LOB'),
  (7, 1, 1, 'Auto Loan', 'AutLn', 'Banking LOB'),
  (8, 4, 3, 'Permanent Life Insurance', 'PermLife', 'Insurance LOB'),
  (9, 2, 2, 'US Savings Bonds', 'USSavBond', 'Investment LOB')"

checkpoint "TASK 1" "Load Data into Portfolio, Category, and Product Tables"

# -----------------------------------------------------------------------------
# TASK 2 - Load Campaigns
# Direct DML creates the same grader-visible state as snippets.py without pip/wget.
# -----------------------------------------------------------------------------
echo "==> TASK 2 — Load Campaigns"
sql "INSERT OR UPDATE INTO Campaigns
  (CampaignId, PortfolioId, CampaignStartDate, CampaignEndDate, CampaignName, CampaignBudget) VALUES
  (1, 1, DATE '2026-07-23', DATE '2026-07-23', 'New Account Reward', 15000),
  (2, 2, DATE '2026-07-23', DATE '2026-07-23', 'Intro to Investments', 5000),
  (3, 2, DATE '2026-07-23', DATE '2026-07-23', 'Youth Checking Accounts', 25000),
  (4, 3, DATE '2026-07-23', DATE '2026-07-23', 'Protect Your Family', 10000)"

checkpoint "TASK 2" "Load Data into Campaigns Table"

# -----------------------------------------------------------------------------
# TASK 3 - Read-only. Optional in speed mode.
# -----------------------------------------------------------------------------
if [[ "$RUN_QUERY_TASKS" == "1" ]]; then
  echo "==> TASK 3 — Query Campaigns"
  sql "SELECT CampaignId, PortfolioId, CampaignStartDate, CampaignEndDate,
              CampaignName, CampaignBudget
       FROM Campaigns
       ORDER BY CampaignId"
else
  echo "==> TASK 3 — skipped (read-only; RUN_QUERY_TASKS=0)"
fi

# -----------------------------------------------------------------------------
# TASK 4 - Add MarketingBudget FIRST, then checkpoint, then write values.
# Keep this separate from Task 5 so grader state follows the lab sequence.
# -----------------------------------------------------------------------------
echo "==> TASK 4 — Add MarketingBudget column"
gcloud spanner databases ddl update "$DATABASE" \
  --instance="$INSTANCE" \
  --project="$PROJECT_ID" \
  --ddl='ALTER TABLE Category ADD COLUMN IF NOT EXISTS MarketingBudget INT64' \
  --quiet

checkpoint "TASK 4" "Add column to Category table"

echo "==> TASK 4 — Update MarketingBudget values"
sql "UPDATE Category
     SET MarketingBudget = CASE
       WHEN CategoryId = 1 AND PortfolioId = 1 THEN 100000
       WHEN CategoryId = 3 AND PortfolioId = 2 THEN 500000
       ELSE MarketingBudget
     END
     WHERE (CategoryId = 1 AND PortfolioId = 1)
        OR (CategoryId = 3 AND PortfolioId = 2)"

if [[ "$RUN_QUERY_TASKS" == "1" ]]; then
  sql "SELECT CategoryId, PortfolioId, MarketingBudget
       FROM Category
       ORDER BY CategoryId"
fi

# -----------------------------------------------------------------------------
# TASK 5 - Create required secondary index, checkpoint, then optional exercise
# and STORING index.
# -----------------------------------------------------------------------------
echo "==> TASK 5 — Create CategoryByCategoryName"
gcloud spanner databases ddl update "$DATABASE" \
  --instance="$INSTANCE" \
  --project="$PROJECT_ID" \
  --ddl='CREATE INDEX IF NOT EXISTS CategoryByCategoryName ON Category(CategoryName)' \
  --quiet

checkpoint "TASK 5" "Add secondary index to Category table"

if [[ "$RUN_QUERY_TASKS" == "1" ]]; then
  echo "==> TASK 5 — Read using CategoryByCategoryName"
  sql "SELECT CategoryId, CategoryName
       FROM Category@{FORCE_INDEX=CategoryByCategoryName}
       ORDER BY CategoryName"
fi

echo "==> TASK 5 — Create CategoryByCategoryName2 (STORING)"
gcloud spanner databases ddl update "$DATABASE" \
  --instance="$INSTANCE" \
  --project="$PROJECT_ID" \
  --ddl='CREATE INDEX IF NOT EXISTS CategoryByCategoryName2 ON Category(CategoryName) STORING (MarketingBudget)' \
  --quiet

if [[ "$RUN_QUERY_TASKS" == "1" ]]; then
  echo "==> TASK 5 — Read using storing index"
  sql "SELECT CategoryId, CategoryName, MarketingBudget
       FROM Category@{FORCE_INDEX=CategoryByCategoryName2}
       ORDER BY CategoryName"
fi

# -----------------------------------------------------------------------------
# TASK 6 - Query plan exploration is read-only and has no listed grader button.
# -----------------------------------------------------------------------------
if [[ "$RUN_QUERY_TASKS" == "1" ]]; then
  echo "==> TASK 6 — Join query"
  sql "SELECT Name, ShortName, CategoryName
       FROM Portfolio
       INNER JOIN Category
       ON Portfolio.PortfolioId = Category.PortfolioId"

  echo "==> TASK 6 — Aggregate query plan"
  plan "SELECT pr.ProductId, COUNT(*) AS ProductCount
        FROM Product AS pr
        WHERE pr.ProductId < 100
        GROUP BY pr.ProductId" >/dev/null

  echo "==> TASK 6 — Co-located join query plan"
  plan "SELECT c.CategoryName, pr.ProductName
        FROM Category AS c, Product AS pr
        WHERE c.PortfolioId = pr.PortfolioId
          AND c.CategoryId = pr.CategoryId" >/dev/null
else
  echo "==> TASK 6 — skipped (read-only query-plan exercise)"
fi

echo
echo "============================================================"
echo "✅ GSP1050 COMPLETE"
echo "Project : $PROJECT_ID"
echo "Instance: $INSTANCE"
echo "Database: $DATABASE"
echo "============================================================"
