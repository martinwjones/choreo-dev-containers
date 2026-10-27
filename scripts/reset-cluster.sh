#!/bin/bash
# Deletes the k3d cluster and recreates an empty one.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Deleting cluster '$CLUSTER_NAME'"
k3d cluster delete "$CLUSTER_NAME"
exec bash "$(dirname "$0")/init-environment.sh"
