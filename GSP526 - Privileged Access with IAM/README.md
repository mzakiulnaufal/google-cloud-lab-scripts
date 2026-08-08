# GSP526 - Privileged Access with IAM: Challenge Lab

Automation scripts for the Google Cloud Skills Boost GSP526 challenge lab.

## Scope

- Enable Privileged Access Manager (PAM)
- Configure the PAM service agent
- Create `pam-entitlement`
- Configure Compute Admin access
- Update maximum duration from 10 hours to 4 hours
- Request temporary privileged access
- Approve the grant with a secondary user
- Revoke the active grant
- Delete the entitlement
- Review PAM audit logs

## Scripts

| Script | Account | Purpose |
| --- | --- | --- |
| `primary.sh` | Primary user | Tasks 1-3 and grant request |
| `secondary.sh` | Secondary user | Approve and revoke grant |
| `cleanup.sh` | Primary user | Task 6 cleanup and audit logs |

## Workflow

```text
Primary
  -> Enable PAM
  -> Create entitlement (10h)
  -> Check progress Task 2
  -> Update entitlement (4h)
  -> Check progress Task 3
  -> Request grant

Secondary
  -> Approve grant
  -> Check progress Task 4
  -> Revoke grant
  -> Check progress Task 5

Primary
  -> Delete entitlement
  -> Review audit logs
  -> Check progress Task 6
```

## Prerequisites

- Google Cloud Shell
- `gcloud` CLI
- A valid GSP526 lab session
- Primary and secondary lab identities

The lab identities are intentionally kept configurable in the scripts. Never commit passwords, tokens, or other credentials.
