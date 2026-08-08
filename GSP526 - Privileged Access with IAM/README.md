# GSP526 - Privileged Access with IAM: Challenge Lab

Automation scripts for the Google Cloud Skills Boost **GSP526 - Privileged Access with IAM: Challenge Lab**.

The lab demonstrates Privileged Access Manager (PAM), entitlement management, just-in-time privilege elevation, dual-control approval, grant revocation, and audit logging.

## Challenge scenario

The workflow uses two lab personas:

- **Cymbal Systems Admin (primary user)** — creates and manages the entitlement and requests temporary elevation.
- **Cymbal Security Lead (secondary user)** — approves and revokes the temporary grant.

## Lab configuration

| Parameter | Configuration |
| --- | --- |
| Entitlement | `pam-entitlement` |
| Location | `global` |
| Role | `Compute Admin` (`roles/compute.admin`) |
| Initial maximum duration | `10 hours` |
| Updated maximum duration | `4 hours` |
| Request duration | `4 hours` |
| Required approvers | `1` |
| Requester justification | Not required by entitlement |

The lab identities are temporary Google Cloud Skills Boost accounts. Use the credentials provided by the active lab session. Do not commit passwords, tokens, or other credentials.

## Prerequisites

- An active GSP526 lab session
- Google Cloud Shell
- `gcloud` CLI
- Access to both the primary and secondary lab accounts
- The primary and secondary accounts must be used in separate browser sessions when the lab requires dual-user approval

## Scripts

The scripts in this repository match the working files in this folder.

| File | Account | Tasks | Purpose |
| --- | --- | --- | --- |
| [`primary.sh`](./primary.sh) | Primary user | Tasks 1-3, Task 4A | Enable PAM, configure the service agent, create the entitlement at 10 hours, update it to 4 hours, and request a 4-hour grant |
| [`secondary.sh`](./secondary.sh) | Secondary user | Task 4B, Task 5 | Find and approve the pending grant, then revoke the active grant |
| [`cleanup.sh`](./cleanup.sh) | Primary user | Task 6 | Verify the grant is no longer active, delete `pam-entitlement`, and review PAM audit logs |

## Workflow

```text
PRIMARY USER
        |
        v
Copy and paste the contents of primary.sh into Google Cloud Shell
        |
        +--> Task 1: Enable PAM API + PAM service-agent role
        |
        +--> Task 2: Create pam-entitlement
        |             Maximum duration = 10 hours
        |
        +--> Check my progress: Task 2
        |
        +--> Task 3: Update maximum duration
        |             10 hours -> 4 hours
        |
        +--> Check my progress: Task 3
        |
        +--> Task 4A: Request 4-hour Compute Admin grant
                      |
                      v
SECONDARY USER
        |
        v
Copy and paste the contents of secondary.sh into Google Cloud Shell
        |
        +--> Task 4B: Approve pending grant
        |             Grant -> ACTIVE
        |
        +--> Check my progress: Task 4
        |
        +--> Task 5: Revoke active grant
                      Grant -> REVOKED
        |
        +--> Check my progress: Task 5
                      |
                      v
PRIMARY USER
        |
        v
Copy and paste the contents of cleanup.sh into Google Cloud Shell
        |
        +--> Task 6: Delete pam-entitlement
        |
        +--> Review PAM audit logs
        |
        +--> Check my progress: Task 6
```

## Usage

### 1. Primary user

Open [`primary.sh`](./primary.sh) in GitHub, copy the **entire contents of the file**, and paste them into Google Cloud Shell while signed in as the primary lab user.

The script performs Tasks 1-3 and creates the grant request for Task 4A.

**Important:** after the script creates the entitlement with a 10-hour maximum duration, stop and click **Check my progress** for Task 2 before allowing the script to continue to Task 3.

After Task 3 is updated to 4 hours, click **Check my progress** again before continuing to the grant request.

### 2. Secondary user

Open a new private/incognito browser window and sign in to Google Cloud as the secondary lab user.

Open [`secondary.sh`](./secondary.sh) in GitHub, copy the **entire contents of the file**, and paste them into the secondary user's Google Cloud Shell.

The script finds the pending grant, approves it, waits for the grant to become `ACTIVE`, then pauses so Task 4 can be checked. After Task 4 is green, it revokes the grant and waits for the state to become `REVOKED`.

Click **Check my progress** for Task 4 before proceeding with the revoke operation, and click **Check my progress** for Task 5 after the grant is revoked.

### 3. Cleanup and audit logs

Return to the primary-user Cloud Shell.

Open [`cleanup.sh`](./cleanup.sh) in GitHub, copy the **entire contents of the file**, and paste them into Google Cloud Shell.

The cleanup script verifies that no active/in-progress grant remains, deletes `pam-entitlement`, and queries the Privileged Access Manager audit logs for the entitlement lifecycle.

After the entitlement is deleted and the audit records are displayed, click **Check my progress** for Task 6.

## Task summary

### Task 1 — Enable Privileged Access Manager

- Enable `privilegedaccessmanager.googleapis.com`.
- Detect the organization ID.
- Configure the Google-managed PAM service agent.
- Grant `roles/privilegedaccessmanager.serviceAgent` to the PAM service agent.

### Task 2 — Create the entitlement

Create `pam-entitlement` in `global` with:

- Role: `roles/compute.admin`
- Maximum duration: `10 hours`
- Requester: primary user
- Requester justification: not mandatory
- Approver: secondary user
- Required approvals: `1`

### Task 3 — Update the entitlement

Change the maximum request duration from:

```text
10 hours
```

to:

```text
4 hours
```

### Task 4 — Request and approve temporary access

The primary user requests a 4-hour Compute Admin grant with a test justification.

The secondary user approves the pending request. The grant should become `ACTIVE`.

### Task 5 — Revoke the grant

The secondary user revokes the active grant. The grant should become `REVOKED`.

### Task 6 — Delete and audit

- Delete `pam-entitlement` after the grant has been revoked.
- Review the Privileged Access Manager audit logs for the entitlement lifecycle.

## Notes

- These scripts are intended for the GSP526 lab environment.
- The lab identities are temporary and should be taken from the active lab session.
- Do not store lab passwords, access tokens, service-account keys, or other secrets in the repository.
- The scripts validate the active account before making IAM/PAM changes.
- The scripts use the active Cloud Shell project, so a Project ID does not need to be hardcoded.
