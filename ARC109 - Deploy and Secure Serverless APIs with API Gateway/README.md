# ARC109 - Deploy and Secure Serverless APIs with API Gateway

Automation script for the Google Cloud Skills Boost **ARC109 - Deploy and Secure Serverless APIs with API Gateway** challenge lab.

The script is designed for **Google Cloud Shell speedruns** and preserves grader-sensitive sequencing: it pauses after every real **Check my progress** objective and waits for confirmation before changing the state for the next task.

## Lab resources

| Resource | Required value |
|---|---|
| Cloud Run function/service | `gcfunction` |
| Runtime | Node.js 22 |
| API ID | `gcfunction-api` |
| API config | `gcfunction-api` |
| Gateway | `gcfunction-api` |
| Gateway display name | `gcfunction API` |
| Backend auth service account | Compute Engine default service account |
| Pub/Sub topic | `demo-topic` |
| Default subscription | `demo-topic-sub` |

`PROJECT_ID`, project number, service account, and region are detected automatically where possible. No participant-specific project IDs, passwords, tokens, API keys, or service-account keys are hardcoded.

## Grader checkpoints

The script pauses at all three grader objectives:

| Task | Objective |
|---|---|
| Task 1 | Create a Cloud Run function |
| Task 2 | Create an API Gateway |
| Task 3 | Create a Pub/Sub Topic and Publish Messages via API Backend |

At every pause:

1. Return to the Skills Boost page.
2. Click **Check my progress**.
3. Confirm the objective is green.
4. Return to Cloud Shell and press **Enter**.

Do not continue to the next task before the current checkpoint is green.

## Usage

### Option 1 — Quick Run from GitHub

Open Cloud Shell using the temporary Skills Boost account, then run:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/ARC109%20-%20Deploy%20and%20Secure%20Serverless%20APIs%20with%20API%20Gateway/arc109.sh")
```

### Option 2: Manual Run (Upload to Cloud Shell)

If you prefer uploading and running the script manually:

1. Download [`arc109.sh`](./arc109.sh) to your local computer.
2. Open **Cloud Shell** in the Google Cloud Console.
3. Click the **More** menu (three dots `⋮` at the top right of the Cloud Shell toolbar) and select **Upload file**.
4. Select `arc109.sh` to upload it to your Cloud Shell home directory.
5. Execute the script in Cloud Shell:

```bash
chmod +x arc109.sh
./arc109.sh
```

### Resume from a completed objective

The script supports `START_TASK` so a valid grader-green resource does not need to be recreated.

If **Task 1 is already green**:

```bash
START_TASK=2 ./arc109.sh
```

If **Tasks 1 and 2 are already green**:

```bash
START_TASK=3 ./arc109.sh
```

This is especially useful if another script already created the Cloud Run function.

### Non-interactive mode

The default is grader-safe interactive mode:

```bash
WAIT_FOR_GRADER=1 ./arc109.sh
```

To disable checkpoint pauses:

```bash
WAIT_FOR_GRADER=0 ./arc109.sh
```

For timed Skills Boost attempts, checkpoint mode is recommended.

## Workflow

```text
TASK 1
  Create gcfunction
       |
       +--> Check my progress -> press Enter when green
       v
TASK 2
  API -> API config -> gateway
       |
       +--> Check my progress -> press Enter when green
       v
TASK 3
  demo-topic + demo-topic-sub
       |
  update gcfunction with Pub/Sub publisher
       |
  invoke through API Gateway
       |
       +--> Check my progress -> press Enter when green
```

## Important 409 recovery

A previously used community solution can leave an existing Cloud Run service named `gcfunction`. Trying to create another second-generation Cloud Function with a conflicting normalized Cloud Run service name can return:

```text
Could not create Cloud Run service gcfunction.
A Cloud Run service with this name already exists.
```

This script avoids deleting a grader-valid resource:

- Task 1 reuses an existing `gcfunction` service instead of creating a duplicate.
- Task 3 updates the existing service with `gcloud run deploy --function` rather than trying to create another Cloud Functions resource.
- Use `START_TASK=2` when Task 1 is already green.

## Speedrun notes

- The gateway/API-config deployment is normally the slowest ARC109 operation.
- No fixed `sleep` is added to successful operations.
- Existing correct resources are reused.
- The function awaits `publishMessage()` before returning HTTP 200, reducing the chance that the grader checks before the Pub/Sub publish has been submitted.
- `demo-topic-sub` is created explicitly to reproduce the console's **Add a default subscription** option.

## Tested behavior

During an ARC109 run on **2026-08-10**:

- Task 1 had already been completed by another script.
- A duplicate `gcloud functions deploy` attempt produced the Cloud Run service `409` collision described above.
- Resuming from Task 2, creating the required API Gateway resources, updating the existing Cloud Run function, creating Pub/Sub resources, and invoking the backend through API Gateway completed the remaining grader objectives successfully.

The script therefore includes the tested recovery/resume behavior in addition to the clean-run Task 1 path.

## Notes

- Intended for the temporary Google Cloud Skills Boost lab environment.
- Run only with the lab-provided student account/project.
- Google may change lab grader behavior or resource requirements over time.
- Never commit temporary lab passwords, access tokens, API keys, or service-account keys.
