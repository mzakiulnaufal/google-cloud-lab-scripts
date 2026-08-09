# GSP1048 - Cloud Spanner: Database Fundamentals

Automation script for the Google Cloud Skills Boost lab **GSP1048 - Cloud Spanner: Database Fundamentals**.

The script is designed for Google Cloud Shell and focuses on completing the grader-visible lab objectives with minimal manual work.

## What it automates

| Task | Automation |
|---|---|
| Task 1 | Creates `banking-instance` with Enterprise edition and 1 node |
| Task 2 | Creates `banking-db` |
| Task 3 | Creates the `Customer` table |
| Task 4 | Inserts both required customer rows and runs `SELECT * FROM Customer` |
| Task 5 | Creates `banking-instance-2` with 2 nodes and `banking-db-2`, then resizes it to 1 node after the grader checkpoint |
| Task 6 | Creates `banking-instance-3` with Terraform |
| Task 7 | Deletes `banking-instance-2` |

## Design

- Automatically detects the active `PROJECT_ID`.
- Detects the lab region from project metadata, then falls back to the current `gcloud` configuration and zone-derived region.
- Builds the Spanner configuration as `regional-<region>` unless `SPANNER_CONFIG` is explicitly supplied.
- Does not hardcode participant project IDs, accounts, passwords, tokens, or service-account keys.
- Provisions the first and second Spanner instances in parallel.
- Prepares Terraform in the background while earlier lab tasks are being checked.
- Is resumable/idempotent where practical.
- Pauses only at grader checkpoints whose required state can be changed by later tasks.

## Usage

### Option 1: Quick Run (Cloud Shell)

Open **Cloud Shell** using the temporary lab account, then run:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/GSP1048%20-%20Cloud%20Spanner%20Database%20Fundamentals/GSP1048.sh")
```

### Option 2: Manual Run (Upload to Cloud Shell)

If you prefer uploading and running the script manually:

1. Download [`GSP1048.sh`](./GSP1048.sh) to your local computer.
2. Open **Cloud Shell** in the Google Cloud Console.
3. Click the **More** menu (three dots `⋮` at the top right of the Cloud Shell toolbar) and select **Upload file**.
4. Select `GSP1048.sh` to upload it to your Cloud Shell home directory.
5. Execute the script in Cloud Shell:

```bash
chmod +x GSP1048.sh
./GSP1048.sh
```

## Grader checkpoints

The script pauses at these points:

1. **Task 2 - Create an instance and database**
2. **Task 3 - Create a schema for your database**
3. **Task 5 - Create an instance and database with CLI**

When a checkpoint appears:

1. Return to the Skills Boost lab tab.
2. Click **Check my progress**.
3. Confirm the objective is green.
4. Return to Cloud Shell and press **Enter**.

Do not continue past the Task 5 checkpoint until it is green. After that checkpoint, the script changes `banking-instance-2` from 2 nodes to 1 node as required by the next lab step.

## Automatic location detection

Detection order:

1. Existing `REGION`, `ZONE`, or `SPANNER_CONFIG` environment variables.
2. Project metadata:
   - `google-compute-default-region`
   - `google-compute-default-zone`
3. `gcloud` defaults:
   - `compute/region`
   - `compute/zone`
4. Derive region from the detected zone.

If automatic detection is unavailable, run with an explicit region:

```bash
REGION=us-central1 ./run.sh
```

Or with an explicit Spanner configuration:

```bash
SPANNER_CONFIG=regional-us-central1 ./run.sh
```

## Notes

- Intended for temporary Google Cloud Skills Boost lab environments.
- Run only with the temporary student account supplied by the active lab.
- Terraform is downloaded into `$HOME/bin` only when it is not already available.
- No lab credentials or participant-specific secrets are stored in this repository.
- Syntax validation can be performed with:

```bash
bash -n run.sh
```
