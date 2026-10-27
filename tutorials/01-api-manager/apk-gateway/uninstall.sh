#!/bin/bash
# Removes this scenario from the cluster (Helm releases, namespace, CRDs).
# Leaves the cluster and the NGINX ingress controller in place.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
NS=apk
# Must not run against another cluster: the CRD cleanup below matches *.wso2.com.
use_cluster "$CLUSTER_NAME" || die "Cannot reach cluster '$CLUSTER_NAME'"

log "Uninstalling Helm releases"
for r in apim-apk-agent apk apim; do
  helm uninstall "$r" -n "$NS" --wait --timeout 5m 2>/dev/null || true
done

log "Deleting namespace $NS"
kubectl delete namespace "$NS" --ignore-not-found --timeout 3m

# Cluster-scoped leftovers: APK, Gateway API and cert-manager CRDs and webhooks.
log "Deleting CRDs and webhooks"
kubectl get crd -o name | grep -E '\.wso2\.com$|gateway\.networking\.k8s\.io$|cert-manager\.io$' \
  | xargs -r kubectl delete --ignore-not-found
kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration -o name \
  | grep -E 'apk|cert-manager|gateway-api' | xargs -r kubectl delete --ignore-not-found

log "Done. Re-deploy with: bash $(realpath --relative-to="$PWD" "$HERE/install.sh")"
