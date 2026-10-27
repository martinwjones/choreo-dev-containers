#!/bin/bash
# Repairs the amp-local cluster after a Mac / Docker VM restart. Each check only acts when
# something is actually broken, so it is safe to run any time. Every problem below was seen
# on 2026-10-24 after Rancher Desktop restarts:
#   1. server node crash-looping: "failed to find interface with specified node ip"
#      (the load balancer container took the server's IP) -> stop/start the cluster
#   2. host.k3d.internal missing from the node's /etc/hosts and CoreDNS NodeHosts
#      (k3d only injects them on `k3d cluster start`) -> image pulls from the in-cluster
#      registry fail, and every *.amp.localhost name used inside the cluster stops resolving
#   3. Controllers CPU-throttled by tiny upstream limits (Argo workflow controller 50m,
#      prometheus-operator 40m) -> they start too slowly for their liveness probes and are
#      killed in a loop; with Argo down, agent builds never run -> raise the limits
#   4. agent gateway runtime crash-looping: "failed to dial xDS server" (started before its
#      controller) -> restart it once the controller is up
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
source "$HERE/common.sh"

SERVER="k3d-$AMP_CLUSTER-server-0"
LB="k3d-$AMP_CLUSTER-serverlb"
NET="k3d-$AMP_CLUSTER"

# 1. Node IP ----------------------------------------------------------------------
if docker logs --tail 50 "$SERVER" 2>&1 | grep -q 'failed to find interface with specified node ip' \
   && [[ "$(docker inspect -f '{{.State.Running}}' "$SERVER")" != true || "$(docker inspect -f '{{.State.Restarting}}' "$SERVER")" == true ]]; then
  warn "Server node lost its IP to the load balancer; restarting the cluster"
  k3d cluster stop "$AMP_CLUSTER" >/dev/null
  k3d cluster start "$AMP_CLUSTER" >/dev/null
fi
use_cluster "$AMP_CLUSTER"
# Straight after a VM restart the API server needs a minute or two before it answers.
for _ in $(seq 60); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done
kubectl wait --for=condition=Ready node --all --timeout 5m >/dev/null

# 2. host.k3d.internal --------------------------------------------------------------
ip_of() { docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$1"; }
GW=$(docker network inspect "$NET" -f '{{(index .IPAM.Config 0).Gateway}}')
if ! docker exec "$SERVER" grep -q 'host.k3d.internal' /etc/hosts; then
  log "Adding host.k3d.internal ($GW) to the node's /etc/hosts"
  docker exec "$SERVER" sh -c "echo '$GW host.k3d.internal' >> /etc/hosts"
fi
if ! kubectl -n kube-system get cm coredns -o jsonpath='{.data.NodeHosts}' | grep -q 'host.k3d.internal'; then
  log "Restoring k3d entries in CoreDNS NodeHosts"
  HOSTS=$(printf '%s host.k3d.internal\n%s %s\n%s %s\n' "$GW" "$(ip_of "$LB")" "$LB" "$(ip_of "$SERVER")" "$SERVER")
  kubectl -n kube-system patch cm coredns --type merge -p "$(jq -nc --arg h "$HOSTS" '{data: {NodeHosts: $h}}')" >/dev/null
fi

# 3. Throttled controllers ---------------------------------------------------------------
# raise_limits <namespace> <deployment> <too-low cpu limit> <cpu limit> <memory limit>
raise_limits() {
  local cpu
  cpu=$(kubectl -n "$1" get deploy "$2" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}')
  [[ "$cpu" == "$3" ]] || return 0
  log "Raising $2's CPU limit ($3 -> $4)"
  kubectl -n "$1" patch deployment "$2" --type=json -p="[
    {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/limits\",\"value\":{\"cpu\":\"$4\",\"memory\":\"$5\"}}]" >/dev/null
  kubectl -n "$1" rollout status "deploy/$2" --timeout 4m >/dev/null
}
raise_limits openchoreo-workflow-plane argo-workflow-controller 50m 500m 256Mi
raise_limits openchoreo-observability-plane prometheus-operator 40m 300m 256Mi

# 4. Agent gateway runtime -------------------------------------------------------------
# Pods are matched by name and old/new pods can coexist, so everything here works on lists.
GW_NS=default-default
gw_ready() { kubectl -n "$GW_NS" get pods --no-headers 2>/dev/null | grep "$1" | grep -q ' 1/1 '; }
for _ in $(seq 60); do gw_ready gateway-controller && break; sleep 5; done
if ! gw_ready gateway-runtime; then
  log "Restarting the agent gateway runtime"
  kubectl -n "$GW_NS" get pods -o name | grep gateway-runtime | xargs -r kubectl -n "$GW_NS" delete --wait=false >/dev/null
  for _ in $(seq 60); do gw_ready gateway-runtime && break; sleep 5; done
fi

log "Pods not Running/Completed:"
kubectl get pods -A --no-headers | grep -vE 'Running|Completed' || echo "  none"
curl -s -o /dev/null -w '  console: HTTP %{http_code}\n' http://console.amp.localhost:8080
