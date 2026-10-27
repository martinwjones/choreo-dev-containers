#!/bin/bash
# Deploys WSO2 API Manager 4.5.0 (control plane) + APK 1.3.0 (gateway) + APK agent.
# Based on https://apk.docs.wso2.com/en/latest/control-plane/apk-as-gateway-in-apim/apk-as-gateway-in-apim-qsg/
# Safe to re-run (helm upgrade --install).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
V="$HERE/values"
NS=apk

# Helm 4 fails on the APK chart (cert-manager webhook not ready during apply).
[[ "$(helm version --template '{{.Version}}')" == v3.* ]] \
  || die "APK 1.3 needs Helm 3 (3.10-3.17). Rebuild the dev container to get the pinned version."

k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1 || bash "$HERE/../../../scripts/init-environment.sh"
use_cluster "$CLUSTER_NAME"
ensure_hosts am.wso2.com api.am.wso2.com idp.am.wso2.com default.gw.wso2.com

log "Adding Helm repositories"
helm repo add wso2apim https://github.com/wso2/helm-apim/releases/download/acp-4.5.0 >/dev/null
helm repo add wso2apk https://github.com/wso2/apk/releases/download/1.3.0-1 >/dev/null
helm repo add wso2apkagent https://github.com/wso2/product-apim-tooling/releases/download/1.3.0 >/dev/null
helm repo update wso2apim wso2apk wso2apkagent >/dev/null

for r in apk apim apim-apk-agent; do unstick_release "$r" "$NS"; done

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Components are installed one at a time (the guide installs them in parallel)
# so that the JVM startups don't overload a laptop-sized Docker VM.
log "[1/3] Installing APK gateway (first run pulls ~10 images)"
helm upgrade --install apk wso2apk/apk-helm --version 1.3.0-1 -n "$NS" \
  -f "$V/upstream/apk-1.3.0-1-cp-enabled-values.yaml" -f "$V/apk-overrides.yaml" \
  --wait --timeout 15m >/dev/null

log "[2/3] Installing API Manager control plane (first start takes 3-6 minutes)"
helm upgrade --install apim wso2apim/wso2am-acp --version 4.5.0-1 -n "$NS" \
  -f "$V/upstream/apim-acp-4.5.0-values.yaml" -f "$V/apim-acp-overrides.yaml" >/dev/null
kubectl rollout status deployment/apim-wso2am-acp-deployment-1 -n "$NS" --timeout 15m

log "[3/3] Installing APK agent"
helm upgrade --install apim-apk-agent wso2apkagent/apim-apk-agent --version 1.3.0 -n "$NS" \
  -f "$V/upstream/apim-apk-agent-1.3.0-values.yaml" -f "$V/apim-apk-agent-overrides.yaml" \
  --wait --timeout 5m >/dev/null

log "Waiting for the portals to answer via ingress"
wait_for_url https://am.wso2.com/publisher 300

kubectl get pods -n "$NS"
cat <<EOF

  Publisher:  https://am.wso2.com/publisher   (admin / admin)
  Devportal:  https://am.wso2.com/devportal
  Gateway:    https://default.gw.wso2.com:9095

  Next: bash $(realpath --relative-to="$PWD" "$HERE/populate.sh")   # create a sample API, app and token
EOF
