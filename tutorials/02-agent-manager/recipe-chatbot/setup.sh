#!/bin/bash
# Prepares everything the recipe chatbot needs except the agent itself:
#   1. Qdrant vector database (namespace recipe-chatbot)
#   2. Recipe ingest: recipes.json -> embeddings (Ollama) -> Qdrant, as a Kubernetes Job
#   3. Ollama registered as an LLM provider in Agent Manager's AI Gateway
#   4. ThunderID (default environment): user chef/chef, SPA app, CORS for the web app
# Safe to re-run. Requires the Agent Manager quick-start (../quick-start/install.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
source "$HERE/common.sh"

use_cluster "$AMP_CLUSTER"

curl -sf -m 5 "$OLLAMA_URL/api/version" >/dev/null \
  || die "Ollama is not reachable at $OLLAMA_URL. Start it on the Mac (ollama serve)."
for m in "$CHAT_MODEL" "$EMBED_MODEL"; do
  curl -s "$OLLAMA_URL/api/tags" | jq -e --arg m "$m" \
    '.models[] | select(.name == $m or .name == ($m + ":latest"))' >/dev/null \
    || die "Ollama model '$m' is missing. On the Mac run: ollama pull $m"
done

# --- 1. Qdrant ---------------------------------------------------------------
log "[1/4] Installing Qdrant"
helm repo add qdrant https://qdrant.github.io/qdrant-helm >/dev/null
helm repo update qdrant >/dev/null
unstick_release qdrant "$NS"
helm upgrade --install qdrant qdrant/qdrant --version "$QDRANT_CHART_VERSION" \
  -n "$NS" --create-namespace -f "$HERE/values/qdrant.yaml" --wait --timeout 5m >/dev/null

# --- 2. Ingest -----------------------------------------------------------------
log "[2/4] Loading recipes into Qdrant (~5 min)"
kubectl -n "$NS" create configmap recipe-ingest --from-file="$HERE/ingest/ingest.py" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" delete job recipe-ingest --ignore-not-found >/dev/null
sed "s|OLLAMA_URL_PLACEHOLDER|$OLLAMA_URL|" "$HERE/ingest/job.yaml" | kubectl apply -f - >/dev/null
# Not `logs -f`: following needs an inotify instance, which the k3d node often runs out of.
kubectl -n "$NS" wait --for=condition=Complete job/recipe-ingest --timeout 15m >/dev/null \
  || die "Recipe ingest failed: kubectl -n $NS logs job/recipe-ingest"
kubectl -n "$NS" logs job/recipe-ingest | tail -3

# --- 3. LLM provider -----------------------------------------------------------
log "[3/4] Registering Ollama as LLM provider '$LLM_PROVIDER'"
TOKEN=$(amp_token)
if call "$TOKEN" GET "$AMP_API/llm-providers/$LLM_PROVIDER" >/dev/null 2>&1; then
  log "LLM provider '$LLM_PROVIDER' already exists"
else
  GATEWAY=$(call "$TOKEN" GET "$AMP_API/gateways" | jq -r --arg e "$AMP_ENV" \
    '[.gateways[] | select(any(.environments[]; .name == $e))][0].uuid')
  # The openai template speaks the OpenAI API, which Ollama serves under /v1.
  call "$TOKEN" POST "$AMP_API/llm-providers" "$(jq -nc --arg id "$LLM_PROVIDER" \
    --arg url "$OLLAMA_URL/v1" --arg gw "$GATEWAY" '{
      id: $id, name: "Ollama on the host Mac", version: "v1.0", context: "/ollama", template: "openai",
      upstream: {main: {url: $url, auth: {type: "none"}}},
      accessControl: {mode: "allow_all", exceptions: []},
      gateways: [$gw]}')" >/dev/null
fi

# --- 4. ThunderID ----------------------------------------------------------------
log "[4/4] Configuring ThunderID: user '$CHEF_USER', app '$WEB_CLIENT_ID', CORS for $WEB_ORIGIN"
IDP_TOKEN=$(idp_token)

if [[ $(call "$IDP_TOKEN" GET "$IDP/users?filter=username%20eq%20%22$CHEF_USER%22" | jq '.totalResults') == 0 ]]; then
  call "$IDP_TOKEN" POST "$IDP/users" "$(jq -nc --arg ou "$IDP_OU" --arg u "$CHEF_USER" --arg p "$CHEF_PASSWORD" '{
    ouId: $ou, type: "Person",
    attributes: {username: $u, password: $p, email: ($u + "@example.com"), given_name: "Chef", family_name: "User", name: "Chef"}}')" >/dev/null
fi

if ! call "$IDP_TOKEN" GET "$IDP/applications" | jq -e --arg c "$WEB_CLIENT_ID" '.applications[] | select(.clientId == $c)' >/dev/null; then
  # Modelled on ThunderID's own Console app: a public browser client using PKCE.
  CONSOLE=$(call "$IDP_TOKEN" GET "$IDP/applications" | jq -r '.applications[] | select(.clientId == "CONSOLE") | .id')
  APP=$(call "$IDP_TOKEN" GET "$IDP/applications/$CONSOLE" | jq -c --arg c "$WEB_CLIENT_ID" --arg o "$WEB_ORIGIN/" '
    del(.id, .logoUrl, .url) | .name = "Recipe Chat" | .description = "Recipe chatbot web app" | .clientId = $c
    | .inboundAuthConfig[0].config.clientId = $c
    | .inboundAuthConfig[0].config.redirectUris = [$o]
    | .inboundAuthConfig[0].config.postLogoutRedirectUris = [$o]')
  call "$IDP_TOKEN" POST "$IDP/applications" "$APP" >/dev/null
fi

ORIGINS=$(call "$IDP_TOKEN" GET "$IDP/server-config/cors" | jq -c --arg o "$WEB_ORIGIN" '.writable.allowedOrigins + [$o] | unique')
call "$IDP_TOKEN" PUT "$IDP/server-config/cors" "{\"allowedOrigins\": $ORIGINS}" >/dev/null

cat <<EOF

  Recipes are loaded, the LLM provider is registered and ThunderID is ready.
  Next: push agent/ to a public GitHub repo, then
    bash $(realpath --relative-to="$PWD" "$HERE/deploy.sh") https://github.com/<you>/<repo>
EOF
