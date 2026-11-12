#!/bin/bash
# Deploys WSO2 API Manager 4.7.0 (all-in-one: Publisher, Devportal, Admin, Key Manager,
# Traffic Manager and Gateway in one pod) into the wso2-cluster k3d cluster.
# Lab for the "Getting Started with WSO2 API Manager" training unit (see README.md).
#
# Optional:
#   MOESIF_APP_ID=<id>  saved to .state/moesif-app-id; enables Moesif analytics
#   PORT_OFFSET=<n>     the port-offset exercise (default 0); see README.md
# Safe to re-run (helm upgrade --install).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../scripts/lib.sh"
V="$HERE/values"
STATE="$HERE/.state"
NS=apim
RELEASE=apim
DEPLOY=apim-wso2am-all-in-one-am-deployment-1
CHART_VERSION=4.7.0-1
# The release index.yaml uses relative chart URLs that 404, so `helm repo add` does not
# work for this release; the packaged chart is downloaded and checked against the
# digest published in that index.
CHART_URL="https://github.com/wso2/helm-apim/releases/download/all-in-one-$CHART_VERSION/wso2am-all-in-one-$CHART_VERSION.tgz"
CHART_SHA256=db7c87915ae0394362957e3fced7d547ce842254948dba8fe4563c97937ab057
PORT_OFFSET="${PORT_OFFSET:-0}"
[[ "$PORT_OFFSET" =~ ^[0-9]+$ ]] || die "PORT_OFFSET must be a number"

k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1 || bash "$HERE/../../scripts/init-environment.sh"
use_cluster "$CLUSTER_NAME"
ensure_hosts am.wso2.com gw.wso2.com

# Tutorial 01 also serves APIM on https://am.wso2.com through the same ingress.
if helm status apim -n apk >/dev/null 2>&1; then
  die "Tutorial 01 (APIM + APK) is installed and also uses am.wso2.com. Remove it first:
  bash tutorials/01-api-manager/apk-gateway/uninstall.sh"
fi

mkdir -p "$STATE"
chmod 700 "$STATE"

log "Fetching chart wso2am-all-in-one $CHART_VERSION"
CHART="$STATE/wso2am-all-in-one-$CHART_VERSION.tgz"
if ! echo "$CHART_SHA256  $CHART" | sha256sum -c --status 2>/dev/null; then
  curl -fsSL -o "$CHART" "$CHART_URL"
  echo "$CHART_SHA256  $CHART" | sha256sum -c --status || die "Chart digest mismatch for $CHART_URL"
fi

# APIM 4.7 needs a symmetric encryption key; the chart refuses to render without one.
# It is generated once and reused, because data encrypted with it cannot be read with another.
[[ -s "$STATE/encryption-key" ]] || openssl rand -hex 16 > "$STATE/encryption-key"

[[ -n "${MOESIF_APP_ID:-}" ]] && printf '%s\n' "$MOESIF_APP_ID" > "$STATE/moesif-app-id"
MOESIF_ID=""
[[ -s "$STATE/moesif-app-id" ]] && MOESIF_ID="$(tr -d '[:space:]' < "$STATE/moesif-app-id")"

# Secret values go in a gitignored values file rather than on the helm command line.
SECRETS="$STATE/apim-secrets.yaml"
( umask 077
  cat > "$SECRETS" <<EOF
wso2:
  moesifAnalytics:
    enabled: $([[ -n "$MOESIF_ID" ]] && echo true || echo false)
    key: "$MOESIF_ID"
  apim:
    portOffset: $PORT_OFFSET
    configurations:
      encryption:
        key: "$(cat "$STATE/encryption-key")"
EOF
)
if [[ -n "$MOESIF_ID" ]]; then
  log "Moesif analytics: enabled (Application ID from .state/moesif-app-id)"
else
  warn "Moesif analytics: disabled. To enable it, re-run with MOESIF_APP_ID=<your Moesif Application ID>"
fi
(( PORT_OFFSET == 0 )) || warn "Port offset $PORT_OFFSET: the chart's ingress still targets 9443/8243, so https://am.wso2.com will not work. See README.md."

unstick_release "$RELEASE" "$NS"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

log "Installing API Manager 4.7.0 (first start takes 3-6 minutes)"
helm upgrade --install "$RELEASE" "$CHART" -n "$NS" \
  -f "$V/upstream/wso2am-all-in-one-$CHART_VERSION-values.yaml" \
  -f "$V/apim-overrides.yaml" \
  -f "$SECRETS" >/dev/null
kubectl rollout status "deployment/$DEPLOY" -n "$NS" --timeout 15m

if (( PORT_OFFSET == 0 )); then
  log "Waiting for the portals to answer via ingress"
  wait_for_url https://am.wso2.com/publisher 300
fi

kubectl get pods,svc -n "$NS"
cat <<EOF

  Publisher:  https://am.wso2.com/publisher   (admin / admin)
  Devportal:  https://am.wso2.com/devportal
  Admin:      https://am.wso2.com/admin
  Carbon:     https://am.wso2.com/carbon
  Gateway:    https://gw.wso2.com              (API calls)

  Look around the installation: bash $(realpath --relative-to="$PWD" "$HERE/explore.sh")
EOF
