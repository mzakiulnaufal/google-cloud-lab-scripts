#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nocasematch

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

fail() {
  echo >&2
  echo "ERROR: $*" >&2
  exit 1
}

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  fail "Google Cloud project ID could not be detected."
fi

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"

if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  fail "No active gcloud account was detected."
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

printf '%s\n' \
  "========================================" \
  " GSP528 - NCC Challenge Lab Speedrun" \
  "========================================" \
  "Project : $PROJECT_ID" \
  "Account : $ACTIVE_ACCOUNT" \
  ""

echo "[1/5] Discovering lab resources..."

# API activation and read-only resource discovery run concurrently.
gcloud services enable networkconnectivity.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet >"$TMP_DIR/api.out" 2>"$TMP_DIR/api.err" &
PID_API=$!

gcloud compute networks list \
  --project="$PROJECT_ID" \
  --format='csv[no-heading](name,routingConfig.routingMode)' \
  >"$TMP_DIR/networks" &
PID_NETWORKS=$!

gcloud compute instances list \
  --project="$PROJECT_ID" \
  --format='csv[no-heading](name,zone,networkInterfaces[0].network,networkInterfaces[0].networkIP)' \
  >"$TMP_DIR/vms" &
PID_VMS=$!

gcloud compute vpn-gateways list \
  --project="$PROJECT_ID" \
  --format='csv[no-heading](name,network,region)' \
  >"$TMP_DIR/gateways" &
PID_GATEWAYS=$!

gcloud compute vpn-tunnels list \
  --project="$PROJECT_ID" \
  --format='csv[no-heading](name,region,vpnGateway,peerGcpGateway,peerExternalGateway,status)' \
  >"$TMP_DIR/tunnels" &
PID_TUNNELS=$!

for pid in "$PID_API" "$PID_NETWORKS" "$PID_VMS" "$PID_GATEWAYS" "$PID_TUNNELS"; do
  wait "$pid" || fail "Resource discovery or API activation failed."
done

mapfile -t NETWORKS < <(
  cut -d',' -f1 "$TMP_DIR/networks" | sed '/^[[:space:]]*$/d'
)

declare -A NETWORK_MODE
while IFS=',' read -r network mode; do
  [[ -n "$network" ]] || continue
  NETWORK_MODE["$network"]="$mode"
done < "$TMP_DIR/networks"

declare -A GATEWAY_NETWORK
while IFS=',' read -r gateway network region; do
  [[ -n "$gateway" ]] || continue
  gateway="${gateway##*/}"
  network="${network##*/}"
  GATEWAY_NETWORK["$gateway"]="$network"
done < "$TMP_DIR/gateways"

resolve_network() {
  local regex="$1"
  local network vm zone vm_network ip

  for network in "${NETWORKS[@]}"; do
    if [[ "$network" =~ $regex ]]; then
      echo "$network"
      return 0
    fi
  done

  while IFS=',' read -r vm zone vm_network ip; do
    if [[ "$vm" =~ $regex ]]; then
      echo "${vm_network##*/}"
      return 0
    fi
  done < "$TMP_DIR/vms"
}

ROUTING_VPC="$(resolve_network '(routing|transit)')"
OFFICE_1_VPC="$(resolve_network '(office[-_]?1|on[-_]?prem.*1|onprem.*1)')"
OFFICE_2_VPC="$(resolve_network '(office[-_]?2|on[-_]?prem.*2|onprem.*2)')"
WORKLOAD_1_VPC="$(resolve_network '(workload.*1)')"
WORKLOAD_2_VPC="$(resolve_network '(workload.*2)')"

# If the routing VPC name is not obvious, select the network that owns
# the largest number of local HA VPN tunnels.
if [[ -z "$ROUTING_VPC" ]]; then
  declare -A VPN_COUNT

  while IFS=',' read -r tunnel region local_gateway peer_gateway external_gateway status; do
    local_gateway="${local_gateway##*/}"
    local_network="${GATEWAY_NETWORK[$local_gateway]:-}"
    [[ -n "$local_network" ]] || continue
    VPN_COUNT["$local_network"]=$(( ${VPN_COUNT[$local_network]:-0} + 1 ))
  done < "$TMP_DIR/tunnels"

  MAX_VPN_COUNT=0
  for network in "${!VPN_COUNT[@]}"; do
    if (( VPN_COUNT[$network] > MAX_VPN_COUNT )); then
      MAX_VPN_COUNT="${VPN_COUNT[$network]}"
      ROUTING_VPC="$network"
    fi
  done
fi

[[ -n "$ROUTING_VPC" ]] || fail "Routing VPC could not be detected."

# Discover the office networks from the peer HA VPN gateways when needed.
declare -A PEER_NETWORKS
while IFS=',' read -r tunnel region local_gateway peer_gateway external_gateway status; do
  local_gateway="${local_gateway##*/}"
  peer_gateway="${peer_gateway##*/}"

  local_network="${GATEWAY_NETWORK[$local_gateway]:-}"
  peer_network="${GATEWAY_NETWORK[$peer_gateway]:-}"

  if [[ "$local_network" == "$ROUTING_VPC" && -n "$peer_network" ]]; then
    PEER_NETWORKS["$peer_network"]=1
  fi
done < "$TMP_DIR/tunnels"

if [[ -z "$OFFICE_1_VPC" ]]; then
  for network in "${!PEER_NETWORKS[@]}"; do
    if [[ "$network" =~ 1 ]]; then
      OFFICE_1_VPC="$network"
      break
    fi
  done
fi

if [[ -z "$OFFICE_2_VPC" ]]; then
  for network in "${!PEER_NETWORKS[@]}"; do
    if [[ "$network" =~ 2 ]]; then
      OFFICE_2_VPC="$network"
      break
    fi
  done
fi

if [[ -z "$OFFICE_1_VPC" || -z "$OFFICE_2_VPC" ]]; then
  mapfile -t SORTED_PEERS < <(printf '%s\n' "${!PEER_NETWORKS[@]}" | sort)

  if [[ -z "$OFFICE_1_VPC" && ${#SORTED_PEERS[@]} -ge 1 ]]; then
    OFFICE_1_VPC="${SORTED_PEERS[0]}"
  fi

  if [[ -z "$OFFICE_2_VPC" ]]; then
    for network in "${SORTED_PEERS[@]}"; do
      if [[ "$network" != "$OFFICE_1_VPC" ]]; then
        OFFICE_2_VPC="$network"
        break
      fi
    done
  fi
fi

[[ -n "$OFFICE_1_VPC" ]] || fail "On-Prem Office 1 VPC could not be detected."
[[ -n "$OFFICE_2_VPC" ]] || fail "On-Prem Office 2 VPC could not be detected."

# Final fallback for workload networks.
if [[ -z "$WORKLOAD_1_VPC" || -z "$WORKLOAD_2_VPC" ]]; then
  CANDIDATES=()

  for network in "${NETWORKS[@]}"; do
    [[ "$network" == "$ROUTING_VPC" ]] && continue
    [[ "$network" == "$OFFICE_1_VPC" ]] && continue
    [[ "$network" == "$OFFICE_2_VPC" ]] && continue
    [[ "$network" == "default" ]] && continue
    CANDIDATES+=("$network")
  done

  mapfile -t CANDIDATES < <(printf '%s\n' "${CANDIDATES[@]}" | sort)

  if [[ -z "$WORKLOAD_1_VPC" && ${#CANDIDATES[@]} -ge 1 ]]; then
    WORKLOAD_1_VPC="${CANDIDATES[0]}"
  fi

  if [[ -z "$WORKLOAD_2_VPC" ]]; then
    for network in "${CANDIDATES[@]}"; do
      if [[ "$network" != "$WORKLOAD_1_VPC" ]]; then
        WORKLOAD_2_VPC="$network"
        break
      fi
    done
  fi
fi

[[ -n "$WORKLOAD_1_VPC" ]] || fail "Workload VPC 1 could not be detected."
[[ -n "$WORKLOAD_2_VPC" ]] || fail "Workload VPC 2 could not be detected."

cat <<EOF_RESOURCES
Detected resources:
  Routing VPC   : $ROUTING_VPC
  Office 1 VPC  : $OFFICE_1_VPC
  Office 2 VPC  : $OFFICE_2_VPC
  Workload VPC1 : $WORKLOAD_1_VPC
  Workload VPC2 : $WORKLOAD_2_VPC
EOF_RESOURCES

collect_tunnels() {
  local target_network="$1"
  local office_number="$2"
  local region=""
  local tunnel tunnel_region local_gateway peer_gateway external_gateway status
  local local_network peer_network
  local -a names=()

  add_unique() {
    local candidate="$1"
    local current

    for current in "${names[@]}"; do
      [[ "$current" == "$candidate" ]] && return 0
    done

    names+=("$candidate")
  }

  while IFS=',' read -r tunnel tunnel_region local_gateway peer_gateway external_gateway status; do
    local_gateway="${local_gateway##*/}"
    peer_gateway="${peer_gateway##*/}"
    tunnel_region="${tunnel_region##*/}"

    local_network="${GATEWAY_NETWORK[$local_gateway]:-}"
    peer_network="${GATEWAY_NETWORK[$peer_gateway]:-}"

    if [[ "$local_network" == "$ROUTING_VPC" && "$peer_network" == "$target_network" ]]; then
      [[ -n "$region" ]] || region="$tunnel_region"
      [[ "$tunnel_region" == "$region" ]] && add_unique "$tunnel"
    fi
  done < "$TMP_DIR/tunnels"

  # Fallback for labs where peerGcpGateway is not populated.
  if (( ${#names[@]} < 2 )); then
    names=()
    region=""

    while IFS=',' read -r tunnel tunnel_region local_gateway peer_gateway external_gateway status; do
      local_gateway="${local_gateway##*/}"
      tunnel_region="${tunnel_region##*/}"
      local_network="${GATEWAY_NETWORK[$local_gateway]:-}"

      [[ "$local_network" == "$ROUTING_VPC" ]] || continue

      if [[ "$tunnel" =~ office[-_]?${office_number} ||
            "$tunnel" =~ on[-_]?prem.*${office_number} ||
            "$tunnel" =~ prem.*${office_number} ]]; then
        [[ -n "$region" ]] || region="$tunnel_region"
        [[ "$tunnel_region" == "$region" ]] && add_unique "$tunnel"
      fi
    done < "$TMP_DIR/tunnels"
  fi

  (( ${#names[@]} >= 2 )) || return 1
  names=("${names[@]:0:2}")

  local -a urls=()
  local name

  for name in "${names[@]}"; do
    urls+=("https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/regions/${region}/vpnTunnels/${name}")
  done

  local joined
  joined="$(IFS=','; echo "${urls[*]}")"
  printf '%s|%s\n' "$region" "$joined"
}

OFFICE_1_INFO="$(collect_tunnels "$OFFICE_1_VPC" 1)" || fail "Office 1 VPN tunnel pair could not be detected."
OFFICE_2_INFO="$(collect_tunnels "$OFFICE_2_VPC" 2)" || fail "Office 2 VPN tunnel pair could not be detected."

IFS='|' read -r OFFICE_1_REGION OFFICE_1_TUNNELS <<< "$OFFICE_1_INFO"
IFS='|' read -r OFFICE_2_REGION OFFICE_2_TUNNELS <<< "$OFFICE_2_INFO"

printf '%s\n' \
  "VPN discovery:" \
  "  Office 1 region : $OFFICE_1_REGION" \
  "  Office 2 region : $OFFICE_2_REGION" \
  ""

create_or_accept_existing() {
  local label="$1"
  shift

  local err_file="$TMP_DIR/${label}.err"

  if "$@" >/dev/null 2>"$err_file"; then
    echo "[OK] $label"
    return 0
  fi

  if grep -qiE 'already exists|ALREADY_EXISTS' "$err_file"; then
    echo "[OK] $label already exists"
    return 0
  fi

  echo "[FAIL] $label" >&2
  cat "$err_file" >&2
  return 1
}

HUB_NAME="gsp528-ncc-hub"
HUB_URI="https://www.googleapis.com/networkconnectivity/v1/projects/${PROJECT_ID}/locations/global/hubs/${HUB_NAME}"

OFFICE_1_VPC_URI="https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/global/networks/${OFFICE_1_VPC}"
WORKLOAD_1_VPC_URI="https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/global/networks/${WORKLOAD_1_VPC}"
WORKLOAD_2_VPC_URI="https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/global/networks/${WORKLOAD_2_VPC}"

echo "[2/5] Creating NCC hub..."

create_or_accept_existing \
  hub \
  gcloud network-connectivity hubs create "$HUB_NAME" \
  --project="$PROJECT_ID" \
  --description="GSP528 NCC challenge lab" \
  --quiet &
PID_HUB=$!

PID_ROUTING_UPDATE=""
if [[ "${NETWORK_MODE[$ROUTING_VPC]:-}" != "GLOBAL" ]]; then
  gcloud compute networks update "$ROUTING_VPC" \
    --project="$PROJECT_ID" \
    --bgp-routing-mode=GLOBAL \
    --quiet >/dev/null &
  PID_ROUTING_UPDATE=$!
fi

wait "$PID_HUB" || fail "NCC hub creation failed."

if [[ -n "$PID_ROUTING_UPDATE" ]]; then
  wait "$PID_ROUTING_UPDATE" || fail "Could not switch the routing VPC to global dynamic routing."
fi

echo "[3/5] Creating Task 1 VPN spokes..."
echo "[4/5] Creating Task 2 VPC spokes..."
echo "[5/5] Creating Task 3 hybrid-named VPC spokes..."

declare -a SPOKE_PIDS=()

# Task 1
create_or_accept_existing \
  office-1-vpn \
  gcloud network-connectivity spokes linked-vpn-tunnels create office-1-vpn \
  --project="$PROJECT_ID" \
  --region="$OFFICE_1_REGION" \
  --hub="$HUB_URI" \
  --vpn-tunnels="$OFFICE_1_TUNNELS" \
  --site-to-site-data-transfer \
  --quiet &
SPOKE_PIDS+=("$!")

create_or_accept_existing \
  office-2-vpn \
  gcloud network-connectivity spokes linked-vpn-tunnels create office-2-vpn \
  --project="$PROJECT_ID" \
  --region="$OFFICE_2_REGION" \
  --hub="$HUB_URI" \
  --vpn-tunnels="$OFFICE_2_TUNNELS" \
  --site-to-site-data-transfer \
  --quiet &
SPOKE_PIDS+=("$!")

# Task 2 and Task 3
# One Workload VPC 1 spoke satisfies both required name fragments.
create_or_accept_existing \
  workload-1-hybrid \
  gcloud network-connectivity spokes linked-vpc-network create workload-1-hybrid \
  --project="$PROJECT_ID" \
  --global \
  --hub="$HUB_URI" \
  --vpc-network="$WORKLOAD_1_VPC_URI" \
  --quiet &
SPOKE_PIDS+=("$!")

create_or_accept_existing \
  workload-2 \
  gcloud network-connectivity spokes linked-vpc-network create workload-2 \
  --project="$PROJECT_ID" \
  --global \
  --hub="$HUB_URI" \
  --vpc-network="$WORKLOAD_2_VPC_URI" \
  --quiet &
SPOKE_PIDS+=("$!")

# Task 3
create_or_accept_existing \
  office-1-hybrid \
  gcloud network-connectivity spokes linked-vpc-network create office-1-hybrid \
  --project="$PROJECT_ID" \
  --global \
  --hub="$HUB_URI" \
  --vpc-network="$OFFICE_1_VPC_URI" \
  --quiet &
SPOKE_PIDS+=("$!")

FAILED=0
for pid in "${SPOKE_PIDS[@]}"; do
  if ! wait "$pid"; then
    FAILED=1
  fi
done

(( FAILED == 0 )) || fail "One or more NCC spokes failed to create."

cat <<'EOF_DONE'

========================================
 GSP528 NCC CONFIGURATION COMPLETE
========================================

Task 1:
  office-1-vpn
  office-2-vpn

Task 2:
  workload-1-hybrid
  workload-2

Task 3:
  office-1-hybrid
  workload-1-hybrid

Click Check my progress for Tasks 1, 2, and 3.
EOF_DONE
