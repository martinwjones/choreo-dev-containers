#!/bin/bash
# Creates (or rebuilds) the recipe-chat agent in Agent Manager from a public GitHub repo,
# waits for the build and deployment, then secures the endpoint with ThunderID (JWT) and
# allows the web app's origin. Writes web/.env for web.sh. Run setup.sh first.
#
#   bash deploy.sh https://github.com/<you>/<repo>          # agent code at the repo root
#   APP_PATH=/agent bash deploy.sh https://github.com/...   # agent code in a subfolder
#   BRANCH=dev bash deploy.sh ...                           # default: main
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
source "$HERE/common.sh"

REPO_URL="${1:?usage: deploy.sh https://github.com/<owner>/<repo>}"
BRANCH="${BRANCH:-main}"
APP_PATH="${APP_PATH:-/}"
[[ "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]] || die "Agent Manager builds only from https://github.com/<owner>/<repo> URLs"

use_cluster "$AMP_CLUSTER"
TOKEN=$(amp_token)
AGENTS="$AMP_API/projects/$AMP_PROJECT/agents"

# Only a 404 means "create": any other failure must not trigger a second create.
EXISTS=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$AGENTS/$AGENT_NAME")
[[ "$EXISTS" == 200 || "$EXISTS" == 404 ]] || die "Could not check for agent '$AGENT_NAME' (HTTP $EXISTS); re-run deploy.sh"
if [[ "$EXISTS" == 200 ]]; then
  log "Agent '$AGENT_NAME' exists; building the latest commit of $BRANCH"
  call "$TOKEN" POST "$AGENTS/$AGENT_NAME/builds" >/dev/null
else
  log "Creating agent '$AGENT_NAME' from $REPO_URL ($BRANCH, $APP_PATH); this starts the first build"
  # chat-api: Agent Manager routes POST /chat to port 8000. PORT=8000 overrides the Python
  # buildpack's default PORT=8080, which main.py would otherwise listen on. The LLM provider's
  # URL and key are injected under the names given in modelConfig (the default names are
  # derived from the config name, e.g. RECIPE_CHAT_LLM_CONFIG_URL).
  call "$TOKEN" POST "$AGENTS" "$(jq -nc --arg n "$AGENT_NAME" --arg url "$REPO_URL" --arg b "$BRANCH" \
    --arg p "$APP_PATH" --arg llm "$LLM_PROVIDER" --arg q "http://qdrant.$NS.svc.cluster.local:6333" \
    --arg chat "$CHAT_MODEL" --arg emb "$EMBED_MODEL" '{
      name: $n, displayName: "Recipe Chat",
      provisioning: {type: "internal", repository: {url: $url, branch: $b, appPath: $p, secretRef: null}},
      agentType: {type: "agent-api", subType: "chat-api"},
      build: {type: "buildpack", buildpack: {language: "python", languageVersion: "3.12", runCommand: "python main.py"}},
      inputInterface: {type: "HTTP", port: 8000},
      configurations: {
        env: [{key: "QDRANT_URL", value: $q}, {key: "CHAT_MODEL", value: $chat},
              {key: "EMBED_MODEL", value: $emb}, {key: "PORT", value: "8000"}],
        enableAutoInstrumentation: true},
      modelConfig: [{providerName: $llm, environmentVariables: [
        {key: "url", name: "OPENAI_URL"}, {key: "apikey", name: "OPENAI_API_KEY"}]}]}')" >/dev/null
fi

log "Waiting for the build (~5 min)"
wait_for_build "$TOKEN" "$AGENT_NAME"

log "Allowing the agent's sandbox to reach Qdrant"
allow_qdrant "$AGENT_NAME"

log "Securing the endpoint with ThunderID tokens and allowing $WEB_ORIGIN"
call "$TOKEN" PUT "$AGENTS/$AGENT_NAME/deploy-settings" "$(jq -nc --arg e "$AMP_ENV" --arg o "$WEB_ORIGIN" '{
  environmentName: $e,
  enableApiKeySecurity: false,
  enableOAuthSecurity: true,
  # forwardToken: the agent reads the (already validated) token to know which user is asking,
  # for its per-user usage limits and trace tags.
  oauthConfig: {issuers: ["ThunderKeyManager"], audiences: [], forwardToken: true},
  corsConfig: {enabled: true, allowOrigin: [$o], allowMethods: ["POST", "OPTIONS"],
               allowHeaders: ["Authorization", "Content-Type"], allowCredentials: false}}')" >/dev/null

AGENT_URL=$(call "$TOKEN" GET "$AGENTS/$AGENT_NAME/endpoints?environment=$AMP_ENV" | jq -r '[.[] | .url][0] // empty')
[[ -n "$AGENT_URL" ]] || die "Could not read the agent's endpoint URL"

cat > "$HERE/web/.env" <<EOF
# Written by deploy.sh
VITE_AGENT_URL=$AGENT_URL
VITE_AUTH_MODE=oauth
VITE_OAUTH_ISSUER=$IDP
VITE_OAUTH_CLIENT_ID=$WEB_CLIENT_ID
VITE_OAUTH_SCOPES=openid profile
EOF

cat <<EOF

  Agent endpoint: $AGENT_URL  (requires a ThunderID token)
  Next: bash $(realpath --relative-to="$PWD" "$HERE/web.sh")   # web app on $WEB_ORIGIN, sign in as $CHEF_USER / $CHEF_PASSWORD
EOF
