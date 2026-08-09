# GSP1050 - Spanner - Defining Schemas and Understanding Query Plans

Automation script for the Google Cloud Skills Boost **GSP1050 - Spanner - Defining Schemas and Understanding Query Plans** lab.

The script is optimized for Cloud Shell speedruns while preserving the grader-sensitive task order. It pauses at each real **Check my progress** checkpoint so the next state-changing task is not executed until the current objective is green.

## Lab configuration

| Resource | Name |
|---|---|
| Spanner instance | `banking-ops-instance` |
| Spanner database | `banking-ops-db` |
| Tables | `Portfolio`, `Category`, `Product`, `Campaigns` |
| Added column | `Category.MarketingBudget` |
| Secondary index | `CategoryByCategoryName` |
| STORING index | `CategoryByCategoryName2` |

The active Google Cloud project is detected automatically from Cloud Shell. No participant-specific project ID, account, password, token, or service-account key is hardcoded.

## Script

| File | Tasks | Purpose |
|---|---|---|
| `gsp1050.sh` | Tasks 1-6 | Load data, update the schema, populate `MarketingBudget`, create secondary indexes, and optionally execute the read/query-plan exercises |

## Grader checkpoints

The script pauses at the four objectives that have **Check my progress** buttons:

| Task | Objective | Points |
|---|---|---:|
| Task 1 | Load Data into Portfolio, Category, and Product Tables | 30 |
| Task 2 | Load Data into Campaigns Table | 20 |
| Task 4 | Add column to Category Table | 20 |
| Task 5 | Add secondary index to Category table | 30 |

At each checkpoint:

1. Return to the Skills Boost lab page.
2. Click **Check my progress**.
3. Confirm the objective is green.
4. Return to Cloud Shell and press **Enter** to continue.

This ordering is intentional. Task 4 and Task 5 schema changes are not pre-created in parallel, which keeps the grader-visible state aligned with the lab sequence.

## Usage

### Option 1 — Quick Run from GitHub

Open Cloud Shell using the temporary Skills Boost account, then run:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/GSP1050%20-%20Spanner%20-%20Defining%20Schemas%20and%20Understanding%20Query%20Plans/gsp1050.sh")
```

### Option 2: Manual Run (Upload to Cloud Shell)

If you prefer uploading and running the script manually:

1. Download [`gsp1050.sh`](./gsp1050.sh) to your local computer.
2. Open **Cloud Shell** in the Google Cloud Console.
3. Click the **More** menu (three dots `⋮` at the top right of the Cloud Shell toolbar) and select **Upload file**.
4. Select `gsp1050.sh` to upload it to your Cloud Shell home directory.
5. Execute the script in Cloud Shell:

```bash
chmod +x gsp1050.sh
./gsp1050.sh
```

### Recommended speedrun mode

The default configuration is already optimized for the grader:

```bash
./gsp1050.sh
```

By default:

- grader checkpoints are enabled;
- read-only Task 3 and Task 6 query-plan exercises are skipped;
- state-changing tasks required by the grader are executed sequentially;
- transient Spanner schema-change aborts are retried automatically.

Equivalent explicit command:

```bash
WAIT_FOR_GRADER=1 RUN_QUERY_TASKS=0 ./gsp1050.sh
```

### Run every lab exercise

To also execute Task 3 queries, index reads, and Task 6 query-plan commands:

```bash
RUN_QUERY_TASKS=1 ./gsp1050.sh
```

### Non-interactive mode

To run without stopping for manual grader confirmation:

```bash
WAIT_FOR_GRADER=0 RUN_QUERY_TASKS=0 ./gsp1050.sh
```

For timed Skills Boost runs, interactive checkpoint mode is recommended so each grader-sensitive state can be verified before the script advances.

## Workflow

```text
TASK 1
  Portfolio -> Category -> Product
       |
       +--> Check my progress -> press Enter when green
       v
TASK 2
  Campaigns
       |
       +--> Check my progress -> press Enter when green
       v
TASK 3
  Query Campaigns (optional/read-only)
       v
TASK 4
  Add MarketingBudget
       |
       +--> Check my progress -> press Enter when green
       |
       +--> Update MarketingBudget values
       v
TASK 5
  Create CategoryByCategoryName
       |
       +--> Check my progress -> press Enter when green
       |
       +--> Create CategoryByCategoryName2 STORING (MarketingBudget)
       v
TASK 6
  Query-plan exercises (optional/read-only)
```

## Spanner `ABORTED: Database schema has changed`

A SQL request issued immediately after a schema update can occasionally return:

```text
ABORTED: Database schema has changed
```

`gsp1050.sh` handles this automatically. SQL commands are retried only when the failure matches a transient Spanner `ABORTED`/schema-change condition, using a short incremental backoff. Successful commands receive no artificial delay.

The retry count can be overridden if needed:

```bash
MAX_SQL_RETRIES=12 ./gsp1050.sh
```

## Rerunning the script

The script is designed to be safely rerunnable inside the same lab session:

- data loading uses `INSERT OR UPDATE`;
- the column is created with `IF NOT EXISTS`;
- indexes are created with `IF NOT EXISTS`;
- `MarketingBudget` values are updated deterministically.

If a Cloud Shell session or command stops midway, rerun the script and continue through the checkpoints.

## Notes

- Intended for the **GSP1050** Google Cloud Skills Boost lab environment.
- Designed for **Google Cloud Shell** and the active temporary lab project.
- Resource names required by the lab remain fixed; participant-specific identities and project IDs are not hardcoded.
- Do not commit lab passwords, access tokens, service-account keys, or other temporary credentials.
- Google may update lab resources or grader behavior over time; review the current lab instructions if the lab changes.
