#!/bin/bash
# Deploys WSO2 Agent Manager 1.0.0 with the official quick-start image.
# Based on https://wso2.com/agent-platform/docs/v1.0.0/get-started/quick-start/
# The image's install.sh creates its own k3d cluster (amp-local) with OpenChoreo 1.2.0
# and Agent Manager on top. Takes 15-20 minutes. Safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
source "$HERE/common.sh"

STATE_DIR="$HERE/.state"
mkdir -p "$STATE_DIR"

# The guide asks for 8 GB / 4 CPUs, and resizing the Docker VM after install can break the cluster.
MEM_GB=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 / 1024 ))
(( MEM_GB >= 7 )) || die "Docker has ${MEM_GB} GB of memory; Agent Manager needs 8 GB. Resize the Docker VM first."
if [[ $(k3d cluster list "$CLUSTER_NAME" -o json 2>/dev/null | jq '.[0].serversRunning // 0') -gt 0 ]]; then
  warn "Cluster '$CLUSTER_NAME' (tutorial 01) is running and needs ~3 GB. Stop it with: k3d cluster stop $CLUSTER_NAME"
fi

start_runner

log "Running the Agent Manager installer (log: $(realpath --relative-to="$PWD" "$STATE_DIR/install.log"))"
amp_run ./install.sh 2>&1 | tee "$STATE_DIR/install.log"

use_cluster "$AMP_CLUSTER"

log "Waiting for the console"
wait_for_url http://console.amp.localhost:8080 300

kubectl get pods -A | grep -vE 'Running|Completed' || true
cat <<EOF

  Console:  http://console.amp.localhost:8080   (admin / admin)

  Switch clusters:  k3d cluster stop $AMP_CLUSTER && k3d cluster start $CLUSTER_NAME
EOF
