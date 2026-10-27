#!/bin/bash
# Creates the shared k3d cluster plus the NGINX ingress controller. Safe to re-run.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Initializing WSO2 Dev Container environment"

if ! k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
  log "Creating k3d cluster '$CLUSTER_NAME' ($K3S_IMAGE)"
  # Traefik is disabled because the WSO2 Helm charts expect NGINX ingress.
  #   80/443 -> NGINX ingress (APIM portals: https://am.wso2.com)
  #   9095   -> APK gateway (https://default.gw.wso2.com:9095)
  k3d cluster create "$CLUSTER_NAME" \
    --image "$K3S_IMAGE" \
    --k3s-arg "--disable=traefik@server:0" \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --port "9095:9095@loadbalancer" \
    --wait
else
  log "Cluster '$CLUSTER_NAME' already exists"
  # Clusters live in the Docker-in-Docker volume and survive a container rebuild,
  # but ~/.kube/config does not, so re-export every running cluster. Stopped
  # clusters are left stopped (another scenario may need the memory).
  for c in $(k3d cluster list -o json | jq -r '.[] | select(.serversRunning > 0) | .name'); do
    k3d kubeconfig merge "$c" --kubeconfig-merge-default >/dev/null
    log "Restored kubectl context k3d-$c"
  done
  if [[ $(k3d cluster list "$CLUSTER_NAME" -o json | jq '.[0].serversRunning') == 0 ]]; then
    log "Cluster '$CLUSTER_NAME' is stopped; start it with: k3d cluster start $CLUSTER_NAME"
    exit 0
  fi
  kubectl config use-context "k3d-$CLUSTER_NAME" >/dev/null
fi

log "Installing NGINX ingress controller"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo update ingress-nginx >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version "$INGRESS_NGINX_VERSION" \
  --namespace ingress-nginx --create-namespace \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=90Mi \
  --wait --timeout 5m >/dev/null

kubectl get nodes
log "Dev Container environment is ready. Deploy a scenario from tutorials/."
