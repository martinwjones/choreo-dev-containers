#!/bin/bash
# Adds API Manager's own (Synapse) gateway, the "universal gateway" 4.5.0, to this scenario, for
# API types APK 1.3 can't serve (WebSocket, WebSub, SSE). It serves the control plane's
# "Default_synapse" environment next to APK's "Default". Also deploys WSO2's sample WebSocket
# backend, for https://apim.docs.wso2.com/en/latest/tutorials/streaming-api/create-and-publish-websocket-api/
# Run install.sh first. Safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
V="$HERE/values"
NS=apk
SAMPLES_NS=samples
# wso2/samples-apim commit with streaming-api-backends/websocket-backend (last changed 2021-03-30)
SAMPLES_COMMIT=c64277589d0ed1f3729451830ba897392901ab60

use_cluster "$CLUSTER_NAME"
helm status apim -n "$NS" >/dev/null 2>&1 || die "API Manager (release apim) isn't installed. Run install.sh first."
ensure_hosts gw.wso2.com websocket.wso2.com

# The gateway chart mounts its keystores from this secret. Use the control plane's default
# keystores, so both sides share certificates (the gateway must trust the control plane's tokens).
if ! kubectl -n "$NS" get secret apim-keystore-secret >/dev/null 2>&1; then
  log "Creating apim-keystore-secret from the control plane's keystores"
  ACP_POD=$(kubectl -n "$NS" get pods -o name | grep acp-deployment | head -1)
  SEC=/home/wso2carbon/wso2am-acp-4.5.0/repository/resources/security
  KS=$(mktemp -d)
  kubectl -n "$NS" exec "$ACP_POD" -- cat "$SEC/wso2carbon.jks" > "$KS/wso2carbon.jks"
  kubectl -n "$NS" exec "$ACP_POD" -- cat "$SEC/client-truststore.jks" > "$KS/client-truststore.jks"
  kubectl -n "$NS" create secret generic apim-keystore-secret \
    --from-file="$KS/wso2carbon.jks" --from-file="$KS/client-truststore.jks" >/dev/null
  rm -rf "$KS"
fi

log "[1/2] Installing the API Manager gateway (first start takes 2-4 minutes)"
helm repo add wso2apimgw https://github.com/wso2/helm-apim/releases/download/universal-gw-4.5.0 >/dev/null
helm repo update wso2apimgw >/dev/null
unstick_release apim-gateway "$NS"
helm upgrade --install apim-gateway wso2apimgw/wso2am-universal-gw --version 4.5.0-1 -n "$NS" \
  -f "$V/upstream/apim-universal-gw-4.5.0-1-values.yaml" -f "$V/apim-gateway-overrides.yaml" >/dev/null
kubectl rollout status deployment/wso2am-gateway-deployment -n "$NS" --timeout 15m

log "[2/2] Deploying the sample backends (WebSocket chat, Pizza Shack mock)"
kubectl create namespace "$SAMPLES_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
SRC=https://raw.githubusercontent.com/wso2/samples-apim/$SAMPLES_COMMIT/streaming-api-backends/websocket-backend
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$SRC/index.js" -o "$TMP/index.js"
curl -fsSL "$SRC/package.json" -o "$TMP/package.json"
kubectl -n "$SAMPLES_NS" create configmap websocket-backend --from-file="$TMP/index.js" --from-file="$TMP/package.json" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f "$HERE/samples/websocket-backend.yaml" >/dev/null
kubectl -n "$SAMPLES_NS" rollout status deployment/websocket-backend --timeout 5m >/dev/null
# The all-in-one API Manager bundles the Pizza Shack sample backend; this split setup doesn't.
kubectl apply -f "$HERE/samples/pizzashack-backend.yaml" >/dev/null
kubectl -n "$SAMPLES_NS" rollout status deployment/pizzashack-backend --timeout 3m >/dev/null

cat <<EOF

  Gateway environment:  Default_synapse (API Manager gateway), next to Default (APK)
  WebSocket clients:    wss://websocket.wso2.com/<context>/<version>/<topic>
  Sample backend:       ws://websocket-backend.$SAMPLES_NS.svc.cluster.local:8080
                        (topics /notifications and /rooms?room=room1|room2|common)
  Pizza Shack backend:  http://pizzashack-backend.$SAMPLES_NS.svc.cluster.local:8080/am/sample/pizzashack/v1/api

  On the Mac, add to /etc/hosts:  127.0.0.1 gw.wso2.com websocket.wso2.com
EOF
