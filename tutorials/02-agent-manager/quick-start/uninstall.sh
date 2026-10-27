#!/bin/bash
# Removes Agent Manager with the upstream uninstall script.
#   bash uninstall.sh                   # remove the platform, keep the amp-local cluster
#   bash uninstall.sh --delete-cluster  # delete the whole amp-local cluster
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
source "$HERE/common.sh"

start_runner
amp_run ./uninstall.sh "$@"

if [[ " $* " == *" --delete-cluster "* || " $* " == *" -d "* ]]; then
  kubectl config delete-context "k3d-$AMP_CLUSTER" >/dev/null 2>&1 || true
  kubectl config delete-cluster "k3d-$AMP_CLUSTER" >/dev/null 2>&1 || true
  kubectl config delete-user "admin@k3d-$AMP_CLUSTER" >/dev/null 2>&1 || true
fi
docker rm -f "$RUNNER" >/dev/null
log "Done. Re-deploy with: bash $(realpath --relative-to="$PWD" "$HERE/install.sh")"
