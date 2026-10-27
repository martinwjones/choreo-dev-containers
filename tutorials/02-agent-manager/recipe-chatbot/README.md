# Recipe Chatbot on WSO2 Agent Manager

A retrieval-augmented (RAG) chatbot that finds recipes from the
[Textual Chef](https://textualchef.com/) feed, hosted and secured by WSO2 Agent Manager:

- **Agent** (Python, FastAPI): built and deployed by Agent Manager from a GitHub repo, with
  automatic tracing.
- **Vector database:** Qdrant, holding one embedded document per recipe.
- **LLM:** Ollama on the host Mac (`llama3.2` for chat, `nomic-embed-text` for embeddings),
  called through Agent Manager's AI Gateway. Free, local, and it uses the Mac's GPU.
- **Web app** (React): users sign in with ThunderID (`chef` / `chef`). The gateway rejects
  requests to the agent without a valid ThunderID token.

```
Browser (localhost:5173) ──sign in──> ThunderID (default-idp.amp.localhost:8080)
   │  Bearer token
   ▼
Agent gateway (default-default.am-gateway.localhost:19080) ── checks the token, CORS
   ▼
recipe-chat agent ──> Qdrant (4,695 recipes, metadata filters)
   │
   └──> AI Gateway (provider "ollama") ──> Ollama on the Mac (host.lima.internal:11434)
```

## How the agent answers

1. **Route:** the model decides whether the message is about food or cooking, and rewrites
   follow-ups ("which of those is easiest?") as standalone searches. A second yes/no check
   catches off-topic questions the first one lets through. Off-topic messages get a polite
   "this is a recipe chatbot" reply.
2. **Filters:** cuisine, course, cooking method, difficulty, diet/restriction, time limit
   ("under 30 minutes", "quick") and calorie limit are read from the user's words with plain
   text matching ([agent/filters.py](agent/filters.py)), not by the model, which would invent filters.
3. **Search:** vector search in Qdrant narrowed by those filters. If nothing matches all of
   them, filters are dropped in stages and the reply says which.
4. **Answer:** the model writes a short intro or answers the cooking question; the recipe list
   underneath, with links, times and diets, is rendered straight from the data.

**Data source:** only the single `recipes.json` feed is downloaded; individual recipe pages are
not fetched, to spare the site. The feed has each recipe's name, description, cuisine, course,
method, main ingredient, difficulty, times, servings, calories, diets, restrictions and tags,
but not the full ingredient list or method. Ingredient searches therefore match the main
ingredient, name and description, and every answer links to the recipe page for the rest.

## Before you start

- Agent Manager installed and running: [quick-start](../quick-start/README.md).
- [Ollama](https://ollama.com/) running on the Mac with both models pulled:
  ```bash
  ollama pull llama3.2
  ollama pull nomic-embed-text
  ```
  The cluster reaches it at `http://host.lima.internal:11434` (Rancher Desktop). With Docker
  Desktop, prefix each script with `OLLAMA_URL=http://host.docker.internal:11434`.
- The agent code in [agent/](agent/) pushed to a **public github.com repository**: Agent Manager
  only builds from GitHub. Ours is <https://github.com/martinwjones/recipe-chat-agent>, whose
  root is the `agent/` folder.

## Run it

```bash
cd tutorials/02-agent-manager/recipe-chatbot
bash setup.sh                                                    # ~2-6 min
bash deploy.sh https://github.com/martinwjones/recipe-chat-agent # ~5 min per build
bash web.sh                                                      # ~1 min
```

| Script | What it does |
| :--- | :--- |
| `setup.sh` | Installs Qdrant (namespace `recipe-chatbot`); loads the recipes with a Kubernetes Job ([ingest/ingest.py](ingest/ingest.py)); registers Ollama as LLM provider `ollama`; creates the ThunderID user `chef`, the browser app `recipe-chat-web` and the CORS origin `http://localhost:5173`. |
| `deploy.sh <repo>` | Creates agent `recipe-chat` (or rebuilds the latest commit), waits for the build, lets the agent's sandbox reach Qdrant, switches the endpoint from API keys to ThunderID tokens, allows the web app's origin, and writes `web/.env`. |
| `web.sh` | Builds the web app and serves it from a Node container on `http://localhost:5173`. Re-run it after editing `web/`. |
| `setup-mcp.sh <repo>` | Optional: publishes the catalog as an MCP server (component `recipe-mcp`) and mints an API key. See [Recipe catalog MCP server](#recipe-catalog-mcp-server). |

All three are safe to re-run.

**The agent's code is a Git submodule.** [agent/](agent/) is the
[recipe-chat-agent](https://github.com/martinwjones/recipe-chat-agent) repository, which Agent
Manager builds from, inside the lab repository. To change the agent:

```bash
cd tutorials/02-agent-manager/recipe-chatbot/agent
git commit -am "Describe the change" && git push          # Agent Manager builds from this
cd ../../../..
git add tutorials/02-agent-manager/recipe-chatbot/agent   # record the new agent version in the lab
git commit -m "Update the recipe agent"
bash tutorials/02-agent-manager/recipe-chatbot/deploy.sh https://github.com/martinwjones/recipe-chat-agent
```

If `agent/` is empty after cloning the lab, run `git submodule update --init`.

## Recipe catalog MCP server

The same catalog is also published as an **MCP server**, so MCP clients (Claude Code, Claude
Desktop, other agents) can search it directly. Its code is [agent/mcp_server.py](agent/mcp_server.py),
in the same GitHub repo as the chat agent and sharing its search code. Agent Manager deploys it
as a second component, **recipe-mcp**, and its gateway requires an API key.

| Tool | What it does |
| :--- | :--- |
| `search_recipes` | Free-text (semantic) search plus optional exact filters: cuisine, course, method, difficulty, diets, ingredients, `max_minutes`, `max_calories`, `limit`. Says which filters it had to drop if nothing matched all of them. |
| `get_recipe` | One recipe's details by id (from a search) or by name. |
| `list_filter_values` | The exact cuisines, courses, methods, difficulties and diets the filters accept. |

```bash
bash setup-mcp.sh https://github.com/martinwjones/recipe-chat-agent   # ~5 min; prints the command below
```

It builds and deploys the component, lets it reach Qdrant, mints an API key (saved to
`.state/mcp-api-key`) and prints how to connect:

```bash
# Claude Code in this Dev Container:
claude mcp add --transport http recipes \
  http://default-default.am-gateway.localhost:19080/recipe-mcp/mcp \
  --header "X-API-Key: $(cat tutorials/02-agent-manager/recipe-chatbot/.state/mcp-api-key)"
```

From the Mac (Claude Code or Claude Desktop), first add
`127.0.0.1 default-default.am-gateway.localhost` to `/etc/hosts`, and make sure port 19080 is
forwarded. Requests without a valid key get HTTP 401.

**Why not an Agent Manager "MCP proxy"?** That is the platform's native way to publish MCP
servers (tool-level access control, attachable to agents as a Tool Configuration), but in
Agent Manager 1.0 a proxy's upstream server must be **publicly** reachable: an SSRF guard
rejects private addresses and cannot be turned off. This server lives inside the cluster, so it
is published as a component instead. Other agents can still use it with its URL and an API key.

## Per-user usage limits

Each signed-in user gets **10 requests and 1,000 LLM tokens per minute**. The minute starts with
their first request. Tokens are everything a request uses: the topic checks, the search
embedding and the answer (a recipe question uses roughly 600-950 tokens, so the token limit
is usually reached first). A request is allowed to finish even if it takes the user past the
token limit; after that, or on the 11th request, the user is blocked until their minute ends
**plus one extra minute**, then both counters reset.

- The web app shows the usage under its header: requests and tokens against the limits, and a
  countdown to the reset ("Unlocks in Ns" while blocked, with Send disabled).
- Blocked requests get HTTP 429 with a `Retry-After` header and the usage in the body.
- The limits live in the agent ([agent/limits.py](agent/limits.py)), because Agent Manager 1.0
  can only rate-limit per agent (on the LLM provider), not per end user. Change them with the
  agent's environment variables `USER_REQUESTS_PER_MINUTE`, `USER_TOKENS_PER_MINUTE` and
  `USER_LIMIT_PENALTY_SECONDS`. Counters are in memory, so they reset when the agent restarts.
- **Who is who:** the gateway validates the user's ThunderID token and forwards it to the agent
  (`forwardToken: true`) in the `x-forwarded-authorization` header. The agent reads the user's
  id (`sub`) and name from it.

**Viewing usage per user:**

- Agent logs, one line per request:
  `usage: user=<id> name=Chef tokens=361 requests=1/10 tokens_total=361/1000`
  (`kubectl logs -n <agent namespace> -l openchoreo.dev/component=recipe-chat -c main`).
- Traces: every LLM span is tagged `traceloop.association.properties.user_id`, `user_name` and
  `session_id`, next to `gen_ai.usage.*_tokens`, so the agent's trace view in the console shows
  who made each call and what it cost.

## How it is wired into Agent Manager

Things the platform needs that are easy to miss (all handled by `deploy.sh`):

- **Port:** Agent Manager routes `chat-api` agents to port 8000, but Google's Python buildpack
  sets `PORT=8080` in the image. The agent is given `PORT=8000` explicitly.
- **LLM variables:** binding the `ollama` provider injects the gateway URL and an API key.
  Their default names come from the config name (`RECIPE_CHAT_LLM_CONFIG_URL`), so `deploy.sh`
  names them `OPENAI_URL` / `OPENAI_API_KEY`. The agent sends the key in an `API-Key` header.
- **Sandbox egress:** agents run in a sandbox whose NetworkPolicy only allows DNS, the platform
  gateways and the public internet. [values/agent-egress-qdrant.yaml](values/agent-egress-qdrant.yaml)
  adds one more path, the agent (and the MCP server) to Qdrant on 6333, without loosening
  anything else. The same sandbox is why embeddings go through the AI Gateway rather than
  straight to the Mac's Ollama.
- **Guardrails:** a guardrail added to the agent's LLM configuration in the console applies to
  every path by default, including `/embeddings`. Message-based guardrails such as PII masking
  fail on embedding requests (`key not found: messages`), so limit them to `/chat/completions`.
- **Redeploying an image:** `POST …/deployments` with only an `imageId` **drops the agent's own
  environment variables** (`PORT`, `QDRANT_URL`, …). Use `deploy.sh`, or send the env with it
  and check with `kubectl exec … env` afterwards.
- **Endpoint security:** `deploy-settings` turns off the default API-key security and turns on
  JWT validation against the environment's ThunderID (`ThunderKeyManager`), plus CORS for
  `http://localhost:5173`.

## Use it

Open **http://localhost:5173** in a browser on the Mac, sign in as **chef / chef**, and try:

- *Quick vegetarian Indian dinners under 30 minutes*
- *What can I make with chickpeas and spinach?*
- *Gluten-free desserts that don't need an oven*, then *which of those is easiest?*
- *What's the difference between baking soda and baking powder?*
- *What's the capital of France?* (gets the polite refusal)

In the Agent Manager console (http://console.amp.localhost:8080) the agent appears under the
Default project as **Recipe Chat**, with its builds, deployment, LLM calls and traces.

The browser must reach ports **5173** (web app), **8080** (ThunderID sign-in) and **19080**
(agent gateway) on the Mac **with the same port numbers**: the sign-in redirects and token
issuer are tied to them. The Dev Container publishes all three with `appPort`. If the container
predates that, check the VS Code **Ports** tab and make sure each is forwarded to the same local
port.

## Check it

```bash
kubectl -n recipe-chatbot get pods                        # qdrant-0 Running
kubectl -n recipe-chatbot run qcount --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- \
  -s -X POST http://qdrant:6333/collections/recipes/points/count -d '{"exact":true}'   # "count":4695
kubectl get workflows -n workflows-default                # agent builds
kubectl get pods -A -l openchoreo.dev/component=recipe-chat   # the agent, 1/1 Running
docker logs recipe-chat-web                               # web app

# A request without a ThunderID token must be rejected (401):
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://default-default.am-gateway.localhost:19080/recipe-chat/chat -d '{"message":"hi"}'
```

## Remove it

```bash
docker rm -f recipe-chat-web
helm uninstall qdrant -n recipe-chatbot && kubectl delete namespace recipe-chatbot
```
Delete the agent (its namespace, including the Qdrant egress policy, goes with it) and the
`ollama` LLM provider in the console. The ThunderID user and app can
be removed in the ThunderID console (http://default-idp.amp.localhost:8080/console).

## Troubleshooting

- **After a Mac or Docker restart, start with `bash ../quick-start/recover.sh`.** It repairs the
  problems seen after restarts: the cluster's lost `host.k3d.internal` entries (builds can't push
  or pull images, internal `*.amp.localhost` calls fail), throttled controllers (builds never
  start), and a stuck agent gateway (agent calls fail).

- **The build fails with `fatal error: lfstack.push` in the `build-image` step** (Apple Silicon):
  x86 buildpack images are being emulated with QEMU. Enable Rosetta in Rancher Desktop
  (Preferences → Virtual Machine → Emulation), then run `deploy.sh` again.
- **The build fails or pods are `Pending`:** memory. Agent Manager uses ~5 GB, and each build
  runs extra pods. Check `kubectl top nodes` and `free -m`, and stop other clusters.
- **The agent answers with `agent invocation failed`:** check the agent's logs in the console
  (or `kubectl logs -n <agent namespace> <pod> -c main`). `Connection refused` on Qdrant means
  the egress policy is missing: re-run `deploy.sh`. Errors on the LLM call usually mean Ollama
  is not running on the Mac, or a model is missing.
- **The build stays without a status for minutes:** the Argo workflow controller is crash-looping.
  Run `../quick-start/recover.sh`, then `deploy.sh` again.
- **http://localhost:5173 hangs or won't load:** check the web app container with
  `docker ps -a --filter name=recipe-chat-web`. If it has exited, run `bash web.sh`. Containers
  started by `web.sh` before 2026-10-26 had no restart policy and stopped with every VM restart;
  they now restart automatically.
- **The web app says the gateway rejected the token:** sign out and in again (tokens last an hour).
- **Sign-in fails with a redirect error:** the web app must be opened on exactly
  `http://localhost:5173`, which is the redirect URI registered in ThunderID.
- **`kubectl logs -f` or a file watcher fails with "too many open files" / `EMFILE`:** the
  k3d node uses up the VM's inotify instances (128 by default). This is why `web.sh` serves a
  build instead of running the Vite dev server. Read logs without `-f`, or raise the limit with
  `sudo sysctl -w fs.inotify.max_user_instances=512` (resets when the VM restarts).
