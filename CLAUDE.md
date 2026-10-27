# CLAUDE.md

Guidance for Claude Code in this repo. See README.md for the user-facing overview.

## What this is

A VS Code Dev Container lab for running WSO2 products on a local k3d cluster (Docker-in-Docker).
Host is a Mac (Rancher/Docker Desktop, Lima VM); everything else runs inside the container.
Scenarios live under `tutorials/`, one folder each, with `install.sh` / `populate.sh` / `uninstall.sh`
and a standalone `README.md` (what it deploys, prerequisites, run, URLs/logins, pause/remove,
differences from upstream, troubleshooting). Keep that README in sync when changing a scenario.

Status:
- `tutorials/01-api-manager/apk-gateway` — **working end to end**: APIM 4.5.0 control plane +
  APK 1.3.0 gateway + APK agent. `populate.sh` creates SampleService → APK, gets a token and
  gets HTTP 200 through `https://default.gw.wso2.com:9095/sample-api/0.1.0/uuid`.
- `tutorials/02-agent-manager/quick-start` — WSO2 Agent Manager 1.0.0 (OpenChoreo 1.2.0 underneath).
  Runs the official `ghcr.io/wso2/amp-quick-start` image as container `amp-quick-start` against
  our DinD socket with `--network=host`; its installer creates a **separate k3d cluster `amp-local`**.
  Console `http://console.amp.localhost:8080` (admin/admin). Install log: `.state/install.log`.
  **Installed and working** (52 pods Running, ~4.8 GB). The default-environment Thunder ID console
  (`http://default-idp.amp.localhost:8080/console`) has a generated admin password, printed at the
  end of the install log. The installer's `print-admin-credentials.sh: No such file` is an
  upstream path bug in the image (harmless); cert-manager `rotationPolicy` warnings are harmless.
- `tutorials/02-agent-manager/recipe-chatbot` — **working end to end** (2026-10-24): RAG recipe
  chatbot on AMP. Agent code lives in its own public repo
  https://github.com/martinwjones/recipe-chat-agent (= the `agent/` folder, a **git submodule**
  of the lab repo since 2026-10-27; commit + push in agent/, `git add` the submodule in the lab
  repo to record the new commit, then `deploy.sh` rebuilds). Qdrant in ns `recipe-chatbot` (4,695 recipes
  from the single `recipes.json` feed — the user chose NOT to fetch per-recipe pages), Ollama on
  the Mac (`llama3.2`, `nomic-embed-text`) via the AI Gateway provider `ollama`, ThunderID user
  `chef`/`chef` + public SPA client `recipe-chat-web`, React app on http://localhost:5173.
  Scripts: `setup.sh`, `deploy.sh <repo>`, `web.sh`. Its README lists the AMP wiring details.
  **MCP server** (2026-10-24): `agent/mcp_server.py` (FastMCP, mcp==1.30.0, stateless JSON) in
  the same repo, deployed by `setup-mcp.sh <repo>` as custom-api component `recipe-mcp`
  (run `python mcp_server.py`, schema `/mcp-openapi.yaml`); endpoint
  `http://default-default.am-gateway.localhost:19080/recipe-mcp/mcp`, header `X-API-Key`
  (key in `.state/mcp-api-key`). Tools: search_recipes, get_recipe, list_filter_values.
- Planned (in README architecture, not built yet): Identity Server, Micro Integrator.

## Multiple clusters

- `wso2-cluster` (tutorial 01) and `amp-local` (tutorial 02) both live in the DinD daemon.
  The Docker VM is 12 GB since 2026-10-26 (Mac has 24 GB), so **run one at a time** (`k3d cluster stop/start`).
- At ~9 GB, agent builds starved the VM of memory (load 40+): 1 s liveness probes failed and
  platform ThunderID, the image registry, OpenChoreo controller-manager, kgateway etc. crash-looped
  (deploys then fail: `failed to get access token`, `failed to update component deployment config`).
  12 GB fixed it. `controller-manager` uses imagePullPolicy Always, so a ghcr.io blip can stall it.
- Every scenario script calls `use_cluster <name>` (lib.sh) first; always check
  `kubectl config current-context` before ad-hoc kubectl/helm. Tutorial 01's uninstall deletes
  all `*.wso2.com` CRDs — never run it against `amp-local`.
- `init-environment.sh` re-exports kubeconfig for running clusters only; it does not start stopped ones.
- Don't resize the Docker VM while `amp-local` exists (upstream warns it can break the cluster).
- **Rancher Desktop must have Rosetta enabled** (Preferences → Virtual Machine → Emulation →
  Enable Rosetta support; VM type VZ). AMP's Python buildpack builds use amd64-only Google
  Cloud Buildpacks images; under QEMU emulation their Go `analyzer` crashes with
  `fatal error: lfstack.push` and the build fails. Check the emulator with a privileged
  container: `/proc/sys/fs/binfmt_misc/` should show rosetta, not `qemu-x86_64`.
- **After any Docker VM / Mac restart run `tutorials/02-agent-manager/quick-start/recover.sh`**
  (idempotent, no-op when healthy). It fixes everything seen on 2026-10-24 restarts:
  serverlb stealing the server's IP (`failed to find interface with specified node ip` →
  stop/start cluster); `host.k3d.internal` missing from the node's /etc/hosts and CoreDNS
  NodeHosts (image push/pull to `host.k3d.internal:10082` fails, and AMP's CoreDNS rewrites of
  `*.amp.localhost` etc. to host.k3d.internal break all internal calls); Argo workflow controller
  (50m) and prometheus-operator (40m) CPU limits so low they're killed by liveness in a loop
  (builds never start / sit with no status) → raised to 500m/300m; agent gateway runtime
  crash-looping with `failed to dial xDS server` → restart it.
- The VM clock jumps forward after the Mac sleeps: log timestamps and pod AGEs can be wildly off.
- The VM's inotify instances (128) are used up by k3d: `kubectl logs -f` and file watchers
  (Vite dev server) fail with "too many open files"/EMFILE.

## Agent Manager agent facts (verified 2026-10-24)

- Agents build only from `https://github.com/<owner>/<repo>`. Python buildpack builds use
  amd64-only Google Cloud Buildpacks (needs Rosetta). Build = Argo workflow in
  `workflows-default`: checkout-source → build-image → publish-image (to
  `host.k3d.internal:10082`) → generate-workload-cr. Agent pods run in
  `dp-default-default-default-<hash>`, label `openchoreo.dev/component=<agent>`.
- `chat-api` agents must listen on 8000, but the buildpack sets `PORT=8080` → set `PORT=8000`.
- LLM provider env var names default to `<CONFIG_NAME>_URL/_API_KEY`; set `environmentVariables`
  (`key: url|apikey`) in `modelConfig` to choose names. Gateway auth header is `API-Key`;
  openai>=3 rejects `api_key=""`, so pass the key as api_key too (gateway ignores the bearer).
- Agent sandbox NetworkPolicy allows egress only to DNS, :8090, data plane, AI gateway :22893,
  :19080 and public 80/443 — anything else in-cluster needs an extra (additive) NetworkPolicy.
- AMP 1.0 MCP proxies reject non-public upstream URLs (`ssrf.ValidateURL` on create and on
  fetch-server-info, no override) → in-cluster MCP servers are published as custom-api
  components instead. custom-api needs `inputInterface {port, basePath, schema.path}`.
- Agent API keys: `POST …/agents/{a}/environments/{envName}/api-keys` — the spec calls the
  param envID but it takes the environment **name**; the key is returned once (`apiKey`).
  Scope names for MCP are `amp:mcp-server:*` (not `amp:mcp-proxy:*`).
- Guardrails added on an agent's LLM config apply to `/*` by default; PII masking then breaks
  `/embeddings` (`key not found: messages`). The user added one on recipe-chat on 2026-10-24
  and removed it again on 2026-10-25; none is configured now. Check the current config via
  `GET …/model-configs/{id}` before assuming one is there.
- Per-user limits (recipe-chat): `forwardToken: true` makes jwt-auth forward the token in
  **`x-forwarded-authorization`** (and strip Authorization) — not in Authorization.
  Traceloop association properties (user_id/user_name/session_id) land on spans in OpenSearch
  (`otel-traces-YYYY-MM-DD`, creds in secret `opensearch-admin-credentials`).
- `POST …/deployments {imageId}` without `env` wipes the agent's user env vars (PORT etc.).
- `PUT …/deploy-settings` switches API-key security to JWT (`ThunderKeyManager`) + CORS and
  triggers a rollout. `PUT …/configurations` replaces user env vars (rollout).
- Env ThunderID admin API: token via `amp-system-client` (secret
  `amp-thunder-default-default-system-client`). Login can be scripted: `/oauth2/authorize` →
  `POST /flow/execute` (executionId, then challengeToken + action + username/password; the
  challengeToken rotates on every call) → `POST /oauth2/auth/callback {authId, assertion}` →
  code → `/oauth2/token` with PKCE.

## Layout

- `.devcontainer/` — Ubuntu 22.04 base + k3d, DinD and kubectl/helm features.
- `scripts/lib.sh` — shared vars (`CLUSTER_NAME`, pinned `K3S_IMAGE`, ingress version) and helpers:
  `log/warn/die`, `ensure_hosts`, `unstick_release`, `wait_for_url`. Source it from every script.
- `scripts/init-environment.sh` — postCreateCommand: creates/starts `wso2-cluster` + NGINX ingress.
- `scripts/reset-cluster.sh` — delete and recreate the cluster.
- `tutorials/<nn>-<product>/<scenario>/values/upstream/` — unmodified upstream Helm values;
  `values/*-overrides.yaml` — our local changes, each with a comment saying why.
- `.state/` (gitignored) — runtime output such as access tokens.

## Conventions

- Scripts: `#!/bin/bash`, `set -euo pipefail`, source `lib.sh`, must be **idempotent / safe to re-run**
  (`helm upgrade --install`, check-before-create on REST objects, `unstick_release` before installs).
- Never edit `values/upstream/*`; put changes in an overrides file layered with a second `-f`.
- Install heavy components one at a time (not in parallel) so JVM startups fit a ~6–8 GB Docker VM.
- Pin versions (charts, images by digest where possible). Explain every workaround in a comment.

## Networking

- Hostnames `am.wso2.com api.am.wso2.com idp.am.wso2.com default.gw.wso2.com` → 127.0.0.1
  (via `runArgs --add-host` and `ensure_hosts`). The host Mac needs the same line in `/etc/hosts`.
- Agent Manager uses 8080, 8443, 11080, 19080, 19443 (also in `appPort`) and `*.amp.localhost`
  / `*.openchoreo.localhost` names, which resolve to 127.0.0.1 without hosts entries.
- Ports 80/443/9095 are published with `appPort` (real `docker run -p`), **not** VS Code port
  forwarding: VS Code remaps 443 to a random port, which breaks APIM redirects to `https://am.wso2.com/`.
- Chain: host port → dev container → k3d loadbalancer (`--port ...@loadbalancer`) → NGINX ingress / APK.
- Credentials `admin`/`admin`; certificates are self-signed (`curl -k`).

## Known gotchas (already solved — don't regress)

- **Helm must be 3.x** (pinned 3.17.3 in devcontainer.json). Helm 4 fails on the APK chart
  (cert-manager webhook not ready during apply).
- **k3s pinned to v1.32** — APK 1.3 supports Kubernetes ≤ 1.32.
- **Traefik disabled** in k3d; WSO2 charts expect NGINX ingress.
- Upstream APIM ACP values point at a deleted RC image → overridden to official
  `wso2/wso2am-acp:4.5.0` by digest (multi-arch, works on Apple Silicon).
- Bitnami images left docker.io/bitnami in 2025 → APK redis uses `bitnamilegacy/redis` and
  `allowInsecureImages: true`.
- APK's own IdP + PostgreSQL disabled (APIM is the key manager) to save ~1 GB.
- APIM startup probe relaxed (slow first start, 3–6 min); memory trimmed.
- The k3d cluster lives in the DinD volume and survives container rebuilds, but `~/.kube/config`
  does not — `init-environment.sh` re-merges the kubeconfig.
- Helm releases can be left `pending-*` after a terminal disconnect → `unstick_release`.

## Dev container persistence

Claude Code state (login, settings, history, memory) is stored in the named volume
`wso2-claude-config` at `/home/vscode/.claude`, with `CLAUDE_CONFIG_DIR` pointing there.
Removing that volume (`docker volume rm` / prune) brings back the login prompt.

## Debugging checklist

```bash
kubectl get pods -A
kubectl get pods -n apk; kubectl describe pod <pod> -n apk; kubectl logs <pod> -n apk
helm list -A
kubectl get apis.dp.wso2.com,applications.cp.wso2.com,subscriptions.cp.wso2.com -n apk
curl -sk -o /dev/null -w '%{http_code}\n' https://am.wso2.com/publisher
```
