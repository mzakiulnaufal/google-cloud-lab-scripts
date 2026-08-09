# GSP528 - Connecting Cloud Networks with NCC: Challenge Lab

Automation script for the Google Cloud Skills Boost **GSP528 - Connecting Cloud Networks with NCC: Challenge Lab**.

The script is optimized for completing the scored NCC configuration with minimal manual input. It discovers the temporary lab project and pre-created networking resources at runtime, so participant-specific project IDs, user accounts, credentials, resource IDs, and keys are not hardcoded.

## Challenge objectives

| Task | Objective | Script resources |
| --- | --- | --- |
| 1 | Connect two on-prem VPCs with NCC | `office-1-vpn`, `office-2-vpn` |
| 2 | Connect Workload VPC 1 and Workload VPC 2 | `workload-1-hybrid`, `workload-2` |
| 3 | Connect On-Prem Office 1 and Workload VPC 1 as VPC spokes | `office-1-hybrid`, `workload-1-hybrid` |

`workload-1-hybrid` intentionally satisfies both naming requirements for Workload VPC 1. Its name contains `workload-1` for Task 2 and `hybrid` for Task 3.

## What the script detects automatically

The script derives the following values from the active Google Cloud Skills Boost session:

- Active Project ID
- Active gcloud account
- Routing VPC
- On-Prem Office 1 VPC
- On-Prem Office 2 VPC
- Workload VPC 1
- Workload VPC 2
- HA VPN gateways
- Office 1 VPN tunnel pair and region
- Office 2 VPN tunnel pair and region

No lab username, Project ID, API key, access token, service-account key, or participant-specific identifier is stored in the script.

## Prerequisites

- An active GSP528 lab session
- Google Cloud Shell
- `gcloud` CLI authenticated with the temporary lab account
- The lab-provided networking resources must still exist

## Usage

### Fastest method

Open **Cloud Shell** using the temporary lab account, then run:

```bash
curl -fsSL 'https://raw.githubusercontent.com/mzakiulnaufal/google-cloud-lab-scripts/main/GSP528%20-%20Connecting%20Cloud%20Networks%20with%20NCC/GSP528.sh' | bash
```

### Upload script from local machine

If you downloaded `GSP528.sh` to your computer, upload the file to Google Cloud Shell using **Upload** in the Cloud Shell menu. After the upload finishes, make the script executable and run it:

```bash
chmod +x GSP528.sh
./GSP528.sh
```

If the file was uploaded to your Cloud Shell home directory but you are currently in another directory, run:

```bash
chmod +x ~/GSP528.sh
~/GSP528.sh
```

The script performs all three scored tasks in one run. After it finishes successfully, click **Check my progress** for Task 1, Task 2, and Task 3.

## Execution strategy

The script prioritizes the resources evaluated by the challenge lab scorer.

1. Enables the Network Connectivity API while discovering the existing VPCs, VMs, HA VPN gateways, and VPN tunnels in parallel.
2. Determines the routing VPC and each office/workload VPC without participant-specific hardcoding.
3. Creates one NCC hub.
4. Ensures the routing VPC uses global dynamic routing when required for site-to-site hybrid route exchange.
5. Creates both VPN spokes for the two on-prem offices with site-to-site data transfer enabled.
6. Creates the VPC spokes needed for workload-to-workload and hybrid-named connectivity.
7. Creates independent spoke operations concurrently to reduce completion time.

The default path does not add SSH or ping operations because those do not create additional NCC resources required by the scored checkpoints and would slow down the speedrun path.

## NCC layout

```text
                               +----------------------+
                               |   gsp528-ncc-hub     |
                               +----------+-----------+
                                          |
           +------------------------------+------------------------------+
           |                     |                     |                  |
           v                     v                     v                  v
   office-1-vpn          office-2-vpn       office-1-hybrid      workload-2
   VPN spoke             VPN spoke          VPC spoke             VPC spoke
           |                     |                     |
           |                     |                     |
           +---- Routing VPC ----+                     |
                                                       |
                                                workload-1-hybrid
                                                VPC spoke
```

## Resource naming

The challenge requires specific text fragments in spoke names:

- Office 1 VPN spoke contains `office-1`
- Office 2 VPN spoke contains `office-2`
- Workload VPC 1 spoke contains `workload-1`
- Workload VPC 2 spoke contains `workload-2`
- Both Task 3 VPC spokes contain `hybrid`

The script uses:

```text
office-1-vpn
office-2-vpn
workload-1-hybrid
workload-2
office-1-hybrid
```

## Notes

- The script is intended specifically for the GSP528 challenge lab environment.
- It uses the project already selected by the active Cloud Shell session.
- Resource discovery is based on the lab topology, network names, VM names, HA VPN gateway relationships, and tunnel metadata.
- Existing matching NCC resources are treated as successful so the script can be rerun after a partial attempt.
- Do not commit lab passwords, API keys, access tokens, cookies, service-account keys, or other credentials.

## References

- Google Cloud Skills Boost: GSP528 - Connecting Cloud Networks with NCC: Challenge Lab
- Google Cloud CLI: `gcloud network-connectivity hubs create`
- Google Cloud CLI: `gcloud network-connectivity spokes linked-vpn-tunnels create`
- Google Cloud CLI: `gcloud network-connectivity spokes linked-vpc-network create`
- Network Connectivity Center documentation: VPC spokes and hybrid spokes
