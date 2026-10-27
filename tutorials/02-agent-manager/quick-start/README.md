# WSO2 Agent Manager 1.0 Quick Start

Runs **WSO2 Agent Manager 1.0.0** (the Agent Management Platform, AMP) on **OpenChoreo 1.2.0**,
in its own k3d cluster called `amp-local`. Agent Manager is a console and API for building,
deploying, governing and observing AI agents. Agents run as sandboxed pods, and LLM calls go
through the AI Gateway.

Based on the upstream guide:
[Agent Manager Quick Start](https://wso2.com/agent-platform/docs/v1.0.0/get-started/quick-start/).

## How it works

The upstream guide runs a quick-start container on your machine. `install.sh` runs that same
official image, `ghcr.io/wso2/amp-quick-start:v1.0.0`, inside the Dev Container instead, so nothing
is installed on your host. The image's own `install.sh` then:

1. Creates the k3d cluster `amp-local` (Kubernetes 1.32) and configures CoreDNS.
2. Installs cert-manager, Gateway API, External Secrets, kgateway and OpenBao.
3. Installs the OpenChoreo control, data, workflow and observability planes
   (with OpenSearch and Prometheus).
4. Installs the API Platform gateway operator, the Thunder identity extension and the AI Gateway.
5. Installs the agent sandbox controller and the AMP core (PostgreSQL, API, console).

## Before you start

- Open the repo in its Dev Container (see the [main README](../../../README.md)).
- Give Docker at least **8 GB of memory and 4 CPUs before installing**. The platform uses ~5 GB.
  Upstream warns that resizing the Docker VM after installing can break the cluster.
- **Apple Silicon Macs:** enable Rosetta in Rancher Desktop (Preferences → Virtual Machine →
  Emulation → Enable Rosetta support, with VM type VZ). Agent Manager builds Python agents with
  x86-only buildpack images, which crash under the default QEMU emulation. Upstream's Colima
  command (`--vz-rosetta`) sets the same thing.
- Stop the API Manager scenario if it is running: `k3d cluster stop wso2-cluster`.
  Both don't fit in 8 GB.
- Ports **8080, 8443, 10082, 11080, 11082, 11085, 19080 and 19443** must be free.
- No hosts-file changes: `*.localhost` names resolve to `127.0.0.1` in browsers and in the
  container.

## Run it

```bash
bash tutorials/02-agent-manager/quick-start/install.sh   # ~10-20 min
```

The full installer output is saved to `tutorials/02-agent-manager/quick-start/.state/install.log`.
Re-running is safe: the upstream installer skips what is already installed.

## Use it

| What | Where | Login |
| :--- | :--- | :--- |
| Agent Manager console | http://console.amp.localhost:8080 | `admin` / `admin` |
| Agent Manager API | http://api.amp.localhost:8080/api/v1 | token from Thunder |
| Thunder ID console (default environment) | http://default-idp.amp.localhost:8080/console | `admin` / generated, see below |
| Traces endpoint (OpenTelemetry) | http://default-default.gateway.localhost:19080/otel | |

The Thunder ID admin password is generated during the install and printed near the end of the log:

```bash
grep 'Password:' tutorials/02-agent-manager/quick-start/.state/install.log | tail -1
```

**Opening the console from your host browser:** the ports above are published by Docker (see
`appPort` in [devcontainer.json](../../../.devcontainer/devcontainer.json)), so the URLs work
as-is. If you installed before rebuilding the Dev Container with those ports, check the VS Code
**Ports** tab: 8080 must be forwarded to local port **8080**, otherwise the login redirects fail.

## Check it

```bash
kubectl config current-context        # should be k3d-amp-local
kubectl get pods -A | grep -vE 'Running|Completed'   # anything listed here is not healthy
kubectl top nodes
```

To run the upstream tools directly, open a shell in the installer container:

```bash
docker exec -it -u wso2-amp -w /home/wso2-amp amp-quick-start bash -l
```

## Pause, resume, remove

```bash
k3d cluster stop amp-local          # pause; everything stays installed
k3d cluster start amp-local         # resume (give it a few minutes)
bash tutorials/02-agent-manager/quick-start/uninstall.sh                   # remove the platform, keep the cluster
bash tutorials/02-agent-manager/quick-start/uninstall.sh --delete-cluster  # delete the amp-local cluster
```

After a Dev Container rebuild the cluster keeps running (it lives in the Docker-in-Docker volume),
and `kubectl` access is restored automatically. The `amp-quick-start` helper container is
recreated by `install.sh` or `uninstall.sh` when needed.

### After a Mac or Docker VM restart

A VM restart restarts the cluster's containers without `k3d cluster start`, and several things
come back broken. Run this, then give the platform a few minutes:

```bash
bash tutorials/02-agent-manager/quick-start/recover.sh
```

It checks for and repairs each of these, and does nothing when the cluster is healthy:

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| `k3d-amp-local-server-0` restarting, `failed to find interface with specified node ip` | the load balancer container took the server's IP | stop and start the cluster |
| Agent builds fail to push or pull images; internal `*.amp.localhost` calls fail | k3d's `host.k3d.internal` entries are missing from the node and from CoreDNS | add them back |
| Agent builds never start; Argo or `prometheus-operator` crash-looping | upstream CPU limits of 40-50m are too low for them to start before their liveness probe | raise the limits |
| Agent and LLM calls fail; `...-gateway-runtime-...` crash-looping with `failed to dial xDS server` | the gateway started before its controller | restart it |

The raised CPU limits are a change to upstream's deployment and are lost if the platform is
reinstalled; `recover.sh` reapplies them.

## What differs from the upstream guide

- The quick-start container runs inside the Dev Container's Docker-in-Docker, not on your host,
  and is driven by our scripts rather than an interactive shell.
- Colima isn't needed: the Dev Container's Docker (Rancher Desktop or Docker Desktop) is used
  instead.
- Nothing else is changed: same image, same installer, same versions.

## Troubleshooting

- **Pods `Pending`, `OOMKilled` or restarting:** not enough memory. Check `kubectl top nodes`,
  stop `wso2-cluster` and confirm Docker has 8 GB.
- **Anything broken after a Mac or Docker restart:** run `recover.sh` (see
  [After a Mac or Docker VM restart](#after-a-mac-or-docker-vm-restart)).
- **"Port … is already in use" at the start:** another process or cluster holds one of the ports
  listed above. `k3d cluster list` and `docker ps` show what is running.
- **`print-admin-credentials.sh: No such file or directory` at the end of the install:** a known
  path bug in the upstream image. Harmless; the install has finished.
- **cert-manager `rotationPolicy` warnings:** informational, can be ignored.
- **Console loads but login fails or redirects to a different port:** see "Opening the console
  from your host browser" above.
