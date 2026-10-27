# Shared settings for the Agent Manager scenario. Source it after scripts/lib.sh.

AMP_VERSION="${AMP_VERSION:-1.0.0}"
AMP_IMAGE="ghcr.io/wso2/amp-quick-start:v$AMP_VERSION"
AMP_CLUSTER=amp-local   # fixed by the quick-start's k3d-config.yaml
RUNNER=amp-quick-start  # container that runs the upstream install/uninstall scripts

# start_runner -> runs the official quick-start image as a long-lived container.
# Like the upstream guide it mounts the Docker socket and uses the host network,
# which here means our Docker-in-Docker daemon and the dev container's network.
start_runner() {
  if [[ "$(docker inspect -f '{{.State.Running}} {{.Config.Image}}' "$RUNNER" 2>/dev/null)" == "true $AMP_IMAGE" ]]; then
    return
  fi
  docker rm -f "$RUNNER" >/dev/null 2>&1 || true
  log "Starting $AMP_IMAGE as container '$RUNNER'"
  # -it keeps the image's interactive entrypoint shell (su - wso2-amp) alive.
  docker run -dit --name "$RUNNER" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --network=host \
    "$AMP_IMAGE" >/dev/null
  # The entrypoint adds wso2-amp to the Docker socket's group; wait for it.
  until docker exec "$RUNNER" test -f /home/wso2-amp/.env_from_docker 2>/dev/null; do sleep 1; done
}

# amp_run <command> -> runs a command as wso2-amp in the runner's home dir with its login profile
amp_run() {
  docker exec -u wso2-amp -w /home/wso2-amp "$RUNNER" bash -lc "$*"
}
