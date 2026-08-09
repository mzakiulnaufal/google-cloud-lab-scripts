# GSP381 - Create and Manage Cloud Spanner Instances: Challenge Lab

Speedrun-oriented Cloud Shell automation for Google Cloud Skills Boost **GSP381 - Create and Manage Cloud Spanner Instances: Challenge Lab**.

The script completes the grader-visible tasks sequentially, automatically detects participant-specific project/location values, and pauses at each actual **Check my progress** objective.

## What it automates

| Task | Automation |
|---|---|
| Task 1 | Creates `banking-ops-instance` in the lab region with 1 node |
| Task 2 | Creates `banking-ops-db` |
| Task 3 | Creates `Portfolio`, `Category`, `Product`, and `Customer` |
| Task 4 | Loads the required 3 Portfolio, 4 Category, and 9 Product rows |
| Task 5 | Downloads `Customer_List_500.csv` and loads all 500 Customer rows with one multi-row Spanner DML operation |
| Task 6 | Adds `MarketingBudget INT64` to `Category` |

## Design goals

- No participant-specific project ID, account, region, zone, password, token, or service-account key hardcoding.
- Automatically detects `PROJECT_ID`, then the lab region from project metadata / gcloud configuration / zone-derived fallback.
- Uses the lab-fixed resources `banking-ops-instance` and `banking-ops-db`.
- Resumable/idempotent where practical using `CREATE TABLE IF NOT EXISTS`, `INSERT OR UPDATE`, and `ADD COLUMN IF NOT EXISTS`.
- Avoids Dataflow for Task 5. The supplied 500-row CSV is converted into one multi-row DML statement, avoiding Dataflow startup and worker service-account overhead.
- Pauses only at the five grader objectives shown by GSP381.
- Treats the Skills Boost grader as the authoritative completion signal instead of failing the run due to fragile local scalar-output parsing.

## Usage

### Option 1: Quick Run (Cloud Shell)

Open **Cloud Shell** using the temporary lab account, then run:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/GSP381%20-%20Create%20and%20Manage%20Cloud%20Spanner%20Instances%20-%20Challenge%20Lab/gsp381.sh")
```

### Option 2: Manual Run (Upload to Cloud Shell)

If you prefer uploading and running the script manually:

1. Download [`gsp381.sh`](./gsp381.sh) to your local computer.
2. Open **Cloud Shell** in the Google Cloud Console.
3. Click the **More** menu (three dots `⋮` at the top right of the Cloud Shell toolbar) and select **Upload file**.
4. Select `gsp381.sh` to upload it to your Cloud Shell home directory.
5. Execute the script in Cloud Shell:

```bash
chmod +x gsp381.sh
./gsp381.sh
```

When the script stops at a checkpoint:

1. Return to the Google Skills lab tab.
2. Click **Check my progress** for the named objective.
3. Confirm the objective is green.
4. Return to Cloud Shell and enter `y`.

## Grader checkpoints

The script stops at:

1. `Create an instance`
2. `Create a database`
3. `Create and Load Tables`
4. `Load Customer table`
5. `Add Column`

## Task 5 implementation

The lab permits any method that loads all 500 Customer records. This script intentionally avoids Dataflow:

1. Downloads `gs://spls/gsp381/Customer_List_500.csv`.
2. Validates that the file contains exactly 500 rows and 3 fields per row.
3. Escapes SQL string literals safely.
4. Generates one `INSERT OR UPDATE ... VALUES (...)` statement containing all 500 records.
5. Executes the DML directly against Cloud Spanner.

A post-load `COUNT(*)` is shown only as a best-effort diagnostic. It is **not** used as a fatal condition because `gcloud spanner databases execute-sql` scalar rendering can vary; a successful DML command followed by the Skills Boost grader checkpoint is the authoritative signal.

## Recovery — Task 6 only

If `Load Customer table` is already green and an older script stopped before Task 6, run:

```bash
chmod +x recovery/resume-task6.sh
./recovery/resume-task6.sh
```

Or directly from GitHub after this folder is pushed:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/GSP381%20-%20Create%20and%20Manage%20Cloud%20Spanner%20Instances%20-%20Challenge%20Lab/recovery/resume-task6.sh")
```

## Lab resources

```text
Spanner instance : banking-ops-instance
Database         : banking-ops-db
Tables           : Portfolio, Category, Product, Customer
Customer source  : gs://spls/gsp381/Customer_List_500.csv
New column       : Category.MarketingBudget INT64
```

## Known fix from testing

An earlier version successfully loaded all 500 Customer rows and the grader turned green, but the script then stopped with:

```text
[ERROR] Customer count=, expected 500
```

The failure was only the script's scalar-output parser. The current version removes that fatal dependency and also makes Task 6 independently resumable.

## Disclaimer

This repository is an automation helper for hands-on educational labs. Review commands before running them and use only the temporary Google Cloud project provided by the lab.
