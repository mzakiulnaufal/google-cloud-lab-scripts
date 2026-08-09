# GSP1049 — Loading Data into Cloud Spanner

Speedrun-oriented Cloud Shell script for the Google Cloud Skills Boost lab **GSP1049 — Loading Data into Cloud Spanner**.

The script completes the lab tasks sequentially and pauses at the actual **Check my progress** checkpoints. It continues only after the user confirms that the previous objective is green.

## What it does

1. Validates the provisioned `banking-instance`, `banking-db`, and `Customer` table.
2. Inserts the Task 2 customer with Spanner DML.
3. Inserts the Task 3 customer through the Python Spanner client library.
4. Pauses until **Insert data through a client library** is green.
5. Performs the Task 4 batch insert through the Python client library.
6. Pauses until **Insert batch data through a client library** is green.
7. Prepares the Cloud Storage/Dataflow dependencies and launches the GCS-to-Cloud-Spanner Dataflow template.
8. Waits until Dataflow reaches `JOB_STATE_DONE`.
9. Pauses until **Load data using Dataflow** is green.
10. Creates the Spanner backup `banking-backup-001` asynchronously.

## Design goals

- No participant-specific project ID, account, region, zone, or key hardcoding.
- Automatically detects the active Google Cloud project and lab location.
- Idempotent/resumable where practical, so already-created lab rows/resources are reused instead of blindly recreated.
- Uses manual grader checkpoints to avoid advancing before the Google Skills objective becomes green.
- Avoids unnecessary waiting except where an actual dependency must finish.

## Dataflow service-account fix

Some fresh lab projects can fail with:

```text
FAILED_PRECONDITION: Please make sure the service account exists and is enabled.
```

`gsp1049.sh` handles this by:

- enabling the Compute Engine, Dataflow, and IAM APIs;
- detecting the Compute Engine default service account;
- enabling it when necessary;
- falling back to another enabled user-managed account or creating a dedicated Dataflow worker account;
- assigning the required worker permissions when allowed by the lab;
- passing the selected account explicitly with `--service-account-email`.

A Task-5-only recovery script is also included at `recovery/resume-task5.sh`.

## Usage

Open **Cloud Shell** using the temporary lab account, then run:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/GSP1049%20-%20Loading%20Data%20into%20Cloud%20Spanner/gsp1049.sh")
```

Or run locally:

```bash
chmod +x gsp1049.sh
./gsp1049.sh
```

When the script stops at a checkpoint:

1. Return to the Google Skills lab tab.
2. Click **Check my progress** for the named objective.
3. Wait until the objective is green.
4. Return to Cloud Shell and enter `y`.

## Resume from Task 5

If Tasks 1–4 are already complete and you only need to recover/retry Dataflow and the backup:

```bash
chmod +x recovery/resume-task5.sh
./recovery/resume-task5.sh
```

## Lab resources used

```text
Spanner instance : banking-instance
Database         : banking-db
Table            : Customer
Dataflow job     : spanner-load
Manifest         : gs://spls/gsp1049/manifest.json
Backup           : banking-backup-001
```

These names are fixed by the lab instructions. Participant-specific values such as `PROJECT_ID`, region, zone, project number, and worker service account are detected at runtime.

## Notes

- Task 1 is primarily an exploration/validation step.
- In the supplied GSP1049 lab instructions, explicit grader checkpoints occur after Tasks 3, 4, and 5.
- Dataflow is the long-running dependency. The script waits for the job to complete before presenting the Task 5 checkpoint.
- The final Spanner backup is launched asynchronously to avoid wasting Cloud Shell time waiting for the backup to become `READY`.

## Disclaimer

This repository is an automation helper for completing a hands-on educational lab. Review the commands before running them and use only the temporary Google Cloud project provided for the lab.
