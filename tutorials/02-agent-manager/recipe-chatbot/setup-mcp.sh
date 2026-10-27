#!/bin/bash
# Publishes the recipe catalog as an MCP server through Agent Manager.
#
# The MCP server (agent/mcp_server.py) lives in the same GitHub repo as the chat agent and is
# deployed as its own custom-api component, "recipe-mcp". The gateway serves it at
# http://default-default.am-gateway.localhost:19080/recipe-mcp/mcp and requires an API key
# (X-API-Key header); this script mints one and prints the command to add it to Claude Code.
#
# Why not an Agent Manager "MCP proxy"? AMP 1.0 only accepts proxies whose upstream server
# is publicly reachable (an SSRF guard with no override), and this server is in-cluster.
#
#   bash setup-mcp.sh https://github.com/<you>/<repo>     # same repo as deploy.sh
#
# Safe to re-run: rebuilds the latest commit and mints a fresh key. Run setup.sh first.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
source "$HERE/common.sh"

REPO_URL="${1:?usage: setup-mcp.sh https://github.com/<owner>/<repo>}"
BRANCH="${BRANCH:-main}"
APP_PATH="${APP_PATH:-/}"
MCP_NAME=recipe-mcp
STATE_DIR="$HERE/.state"
[[ "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]] || die "Agent Manager builds only from https://github.com/<owner>/<repo> URLs"

use_cluster "$AMP_CLUSTER"
TOKEN=$(amp_token)
AGENTS="$AMP_API/projects/$AMP_PROJECT/agents"

EXISTS=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$AGENTS/$MCP_NAME")
[[ "$EXISTS" == 200 || "$EXISTS" == 404 ]] || die "Could not check for '$MCP_NAME' (HTTP $EXISTS); re-run setup-mcp.sh"
if [[ "$EXISTS" == 200 ]]; then
  log "'$MCP_NAME' exists; building the latest commit of $BRANCH"
  call "$TOKEN" POST "$AGENTS/$MCP_NAME/builds" >/dev/null
else
  log "Creating '$MCP_NAME' from $REPO_URL ($BRANCH, $APP_PATH); this starts the first build"
  # custom-api: the gateway routes the operations in mcp-openapi.yaml to port 8000. PORT=8000
  # overrides the Python buildpack's PORT=8080. Embeddings go through the bound "ollama" LLM
  # provider, because the sandbox blocks direct calls to the Mac's Ollama.
  call "$TOKEN" POST "$AGENTS" "$(jq -nc --arg n "$MCP_NAME" --arg url "$REPO_URL" --arg b "$BRANCH" \
    --arg p "$APP_PATH" --arg llm "$LLM_PROVIDER" --arg q "http://qdrant.$NS.svc.cluster.local:6333" \
    --arg emb "$EMBED_MODEL" '{
      name: $n, displayName: "Recipe Catalog MCP",
      provisioning: {type: "internal", repository: {url: $url, branch: $b, appPath: $p, secretRef: null}},
      agentType: {type: "agent-api", subType: "custom-api"},
      build: {type: "buildpack", buildpack: {language: "python", languageVersion: "3.12", runCommand: "python mcp_server.py"}},
      inputInterface: {type: "HTTP", port: 8000, basePath: "/", schema: {path: "/mcp-openapi.yaml"}},
      configurations: {
        env: [{key: "QDRANT_URL", value: $q}, {key: "EMBED_MODEL", value: $emb}, {key: "PORT", value: "8000"}],
        enableAutoInstrumentation: true},
      modelConfig: [{providerName: $llm, environmentVariables: [
        {key: "url", name: "OPENAI_URL"}, {key: "apikey", name: "OPENAI_API_KEY"}]}]}')" >/dev/null
fi

log "Waiting for the build (~5 min)"
wait_for_build "$TOKEN" "$MCP_NAME"

log "Allowing the MCP server's sandbox to reach Qdrant"
allow_qdrant "$MCP_NAME"

URL=$(call "$TOKEN" GET "$AGENTS/$MCP_NAME/endpoints?environment=$AMP_ENV" | jq -r '[.[] | .url][0] // empty')
[[ -n "$URL" ]] || die "Could not read the endpoint URL of '$MCP_NAME'"
MCP_URL="${URL%/}/mcp"

log "Minting an API key for MCP clients"
# The path parameter is called envID in the API spec, but it takes the environment's name.
KEY=$(call "$TOKEN" POST "$AGENTS/$MCP_NAME/environments/$AMP_ENV/api-keys" \
  "$(jq -nc --arg d "MCP clients $(date -u +%Y-%m-%dT%H%MZ)" '{displayName: $d}')" | jq -r '.apiKey // empty')
[[ -n "$KEY" ]] || die "The platform did not return an API key"
mkdir -p "$STATE_DIR"
( umask 077; printf '%s\n' "$KEY" > "$STATE_DIR/mcp-api-key" )

cat <<EOF

  MCP endpoint: $MCP_URL
  API key:      saved to $(realpath --relative-to="$PWD" "$STATE_DIR/mcp-api-key") (header X-API-Key)

  Claude Code (in this Dev Container):
    claude mcp add --transport http recipes $MCP_URL --header "X-API-Key: \$(cat $STATE_DIR/mcp-api-key)"

  From the Mac, add this line to /etc/hosts first, so the gateway's host name resolves:
    127.0.0.1 default-default.am-gateway.localhost
EOF
