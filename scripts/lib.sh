# Shared helpers for lab scripts. Source it: source "$(dirname "$0")/lib.sh"

CLUSTER_NAME="${CLUSTER_NAME:-wso2-cluster}"
# APK 1.3 supports Kubernetes <= 1.32, so the k3s version is pinned.
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.32.13-k3s1}"
INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-4.15.1}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ensure_hosts host1 host2 ... -> maps each name to 127.0.0.1 in /etc/hosts
ensure_hosts() {
  local h
  for h in "$@"; do
    if ! grep -qE "^[^#]*[[:space:]]$h([[:space:]]|\$)" /etc/hosts; then
      echo "127.0.0.1 $h" | sudo tee -a /etc/hosts >/dev/null
      log "Added $h to /etc/hosts"
    fi
  done
}

# use_cluster <name> -> starts the k3d cluster if stopped and makes it the current kubectl/helm
# context. Every scenario script calls this first, because several clusters can exist side by side.
use_cluster() {
  k3d cluster start "$1" >/dev/null
  k3d kubeconfig merge "$1" --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null
  log "Using cluster '$1' (kubectl context k3d-$1)"
}

# unstick_release <release> <namespace> -> rolls back a release left in a pending-*
# state (e.g. the terminal disconnected mid-install) so it can be upgraded again.
unstick_release() {
  local status
  status=$(helm status "$1" -n "$2" -o json 2>/dev/null | jq -r .info.status) || return 0
  if [[ "$status" == pending-* ]]; then
    warn "Release $1 is stuck in '$status'; rolling it back"
    helm rollback "$1" -n "$2" --wait --timeout 5m >/dev/null
  fi
}

# wait_for_url <url> [timeout_seconds] -> waits until the URL returns a non-5xx response
wait_for_url() {
  local url="$1" timeout="${2:-600}" start code
  start=$(date +%s)
  until code=$(curl -sk -o /dev/null -w '%{http_code}' "$url") && [[ "$code" =~ ^[234] ]]; do
    (( $(date +%s) - start > timeout )) && die "Timed out waiting for $url (last HTTP $code)"
    sleep 10
  done
}
