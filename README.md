# Google Cloud Skills Scripts

Working automation scripts for Google Cloud Skills Boost labs and challenge labs.

## Structure

Each lab uses the naming convention:

```text
<CODE> - <Skill Name>/
```

Example:

```text
GSP526 - Privileged Access with IAM/
```

Each lab folder contains its own README and executable scripts.

## Labs

| Code | Skill | Status |
| --- | --- | --- |
| GSP526 | [Privileged Access with IAM](./GSP526%20-%20Privileged%20Access%20with%20IAM) | Needs Testing |
| GSP528 | [Connecting Cloud Networks with NCC](./GSP528%20-%20Connecting%20Cloud%20Networks%20with%20NCC) | Working |
| GSP1049 | [Loading Data into Cloud Spanner](./GSP1049%20-%20Loading%20Data%20into%20Cloud%20Spanner) | Working |

## Notes

- Scripts are designed for Google Cloud Shell unless stated otherwise.
- Temporary lab identities should be supplied through environment variables or adjusted for the active lab session.
- Do not commit passwords, API keys, access tokens, or other credentials.
