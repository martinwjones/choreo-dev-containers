#!/bin/bash
# Removes this scenario (Helm release + namespace). Leaves the cluster, the NGINX ingress
# controller and .state/ (encryption key, Moesif Application ID) in place.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../scripts/lib.sh"
NS=apim
use_cluster "$CLUSTER_NAME" || die "Cannot reach cluster '$CLUSTER_NAME'"

log "Uninstalling Helm release"
helm uninstall apim -n "$NS" --wait --timeout 5m 2>/dev/null || true

log "Deleting namespace $NS"
kubectl delete namespace "$NS" --ignore-not-found --timeout 3m

log "Done. Re-deploy with: bash $(realpath --relative-to="$PWD" "$HERE/install.sh")"
