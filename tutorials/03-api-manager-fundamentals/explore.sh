#!/bin/bash
# Walks through the "key directories", "key configuration files" and "port offset" parts
# of the training unit against the running APIM pod. Read-only.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../scripts/lib.sh"
NS=apim
DEPLOY=apim-wso2am-all-in-one-am-deployment-1

use_cluster "$CLUSTER_NAME"
kubectl get "deployment/$DEPLOY" -n "$NS" >/dev/null 2>&1 \
  || die "API Manager is not installed. Run: bash $(realpath --relative-to="$PWD" "$HERE/install.sh")"

in_pod() { kubectl exec -n "$NS" "deployment/$DEPLOY" -c wso2am -- bash -c "$1"; }

log "<APIM_HOME> (the zip's root folder; \$WSO2_SERVER_HOME in the container)"
in_pod 'echo "$WSO2_SERVER_HOME"; ls -la "$WSO2_SERVER_HOME"'

log "Key configuration files in <APIM_HOME>/repository/conf"
in_pod 'ls -la "$WSO2_SERVER_HOME"/repository/conf/deployment.toml "$WSO2_SERVER_HOME"/repository/conf/log4j2.properties'

log "deployment.toml: [server] section (hostname, port offset)"
in_pod 'sed -n "/^\[server\]/,/^\[/p" "$WSO2_SERVER_HOME"/repository/conf/deployment.toml | sed "\$d"'

log "deployment.toml: analytics (Moesif) section"
in_pod 'sed -n "/^\[apim.analytics/,/^\[apim.ai\]/p" "$WSO2_SERVER_HOME"/repository/conf/deployment.toml | sed "\$d" | grep -v "moesifKey"; grep -q "^moesifKey" "$WSO2_SERVER_HOME"/repository/conf/deployment.toml && echo "moesifKey = <set, hidden>" || true'

log "Ports the server reports at startup (offset already applied)"
kubectl logs -n "$NS" "deployment/$DEPLOY" -c wso2am 2>/dev/null \
  | grep -E 'Mgt Console URL|API Developer Portal Default Context|API Publisher Default Context|Pass-through HTTPS? Listener started' \
  | sed -E 's/^.*(Mgt Console|API Dev|API Pub|Pass-through)/\1/' | sort -u || true

log "Kubernetes service ports (also shifted by the offset)"
kubectl get svc -n "$NS" -o custom-columns='SERVICE:.metadata.name,PORTS:.spec.ports[*].port'
