# GSP081 — Cloud Run Functions: Qwik Start - Console

Speedrun-oriented Cloud Shell script for **Google Cloud Skills Boost GSP081 — Cloud Run Functions: Qwik Start - Console**.

The script focuses on the grader-visible lab state: it deploys the required public Cloud Run function, applies the requested revision scaling limit, invokes the function with the lab payload, and thereby generates request/log activity without requiring the console workflow.

## What it does

1. Detects the active lab project automatically.
2. Detects the lab region from project metadata or existing `gcloud` configuration.
3. Enables the APIs required for a Cloud Run function source deployment.
4. Creates the Node.js `helloHttp` source locally in Cloud Shell.
5. Deploys the service as `gcfunction`.
6. Uses the second-generation Cloud Run execution environment.
7. Sets the revision maximum instance count to `5`.
8. Allows unauthenticated/public HTTP invocation.
9. Sends `{"message":"Hello World!"}` to the deployed function.
10. Verifies that the response is `Hello World!`.

## Design goals

- No participant-specific project ID, account, key, or credential hardcoding.
- Automatic project and region discovery.
- Focus on the actual graded resource state instead of reproducing console clicks.
- Minimal waiting beyond the Cloud Run build/deployment dependency.
- Safe to rerun: deploying the same service updates/reuses `gcfunction` rather than creating participant-specific resources.

## Usage

### Option 1 — Quick Run from GitHub

Open Cloud Shell using the temporary Skills Boost account, then run:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/GSP081%20-%20Cloud%20Run%20Functions%20Qwik%20Start%20-%20Console/gsp081.sh")
```

After the script prints both objectives as done, return to the lab page and click **Check my progress** for:

1. **Deploy the function**
2. **Test the function**

### Option 2: Manual Run (Upload to Cloud Shell)

If you prefer uploading and running the script manually:

1. Download [`gsp081.sh`](./gsp081.sh) to your local computer.
2. Open **Cloud Shell** in the Google Cloud Console.
3. Click the **More** menu (three dots `⋮` at the top right of the Cloud Shell toolbar) and select **Upload file**.
4. Select `gsp081.sh` to upload it to your Cloud Shell home directory.
5. Execute the script in Cloud Shell:

```bash
chmod +x gsp081.sh
./gsp081.sh
```

### Region override

Normally the region is detected automatically. If a particular lab session does not expose its region through project metadata or `gcloud` configuration, provide it explicitly:

```bash
REGION_OVERRIDE=us-central1 ./gsp081.sh
```

Replace `us-central1` with the region shown by that lab session.

## Lab resources

```text
Cloud Run service/function : gcfunction
Function entry point       : helloHttp
Trigger                    : HTTP/HTTPS
Authentication             : Public / unauthenticated
Execution environment      : Second generation
Revision max instances     : 5
Test payload               : {"message":"Hello World!"}
Expected response           : Hello World!
```

## Task 5 answers

```text
Cloud Run functions is a serverless execution environment for event-driven services on Google Cloud.
Answer: True

Which type of trigger is used while creating Cloud Run functions in the lab?
Answer: HTTPS
```

## Notes

- The lab instructions use the Google Cloud console, but the same target Cloud Run function can be deployed from Cloud Shell.
- The test request also creates request/log activity, so opening the Logs UI is not required by the automation itself.
- Use only the temporary Google Cloud project and credentials supplied by the lab.

## Disclaimer

This repository is an automation helper for completing a hands-on educational lab. Review the commands before running them and use only the temporary Google Cloud project provided for the lab.
