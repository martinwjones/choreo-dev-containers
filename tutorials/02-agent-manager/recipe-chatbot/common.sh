# Shared settings for the recipe chatbot. Source it after scripts/lib.sh.

AMP_CLUSTER=amp-local
NS=recipe-chatbot
QDRANT_CHART_VERSION=1.19.2

# Ollama on the host Mac. Rancher Desktop exposes the host as host.lima.internal;
# with Docker Desktop use OLLAMA_URL=http://host.docker.internal:11434.
OLLAMA_URL="${OLLAMA_URL:-http://host.lima.internal:11434}"
CHAT_MODEL="${CHAT_MODEL:-llama3.2}"
EMBED_MODEL="${EMBED_MODEL:-nomic-embed-text}"

AMP_API=http://api.amp.localhost:8080/api/v1/orgs/default
AMP_PROJECT=default
AMP_ENV=default
AGENT_NAME=recipe-chat
LLM_PROVIDER=ollama

IDP=http://default-idp.amp.localhost:8080   # the default environment's ThunderID
IDP_OU=01900000-0000-7000-8000-000000000001 # its "default" organisation unit
WEB_ORIGIN=http://localhost:5173
WEB_CLIENT_ID=recipe-chat-web
CHEF_USER=chef
CHEF_PASSWORD=chef

# amp_token -> Agent Manager API token (client credentials of the platform's API client).
# Scopes must be requested explicitly: Thunder grants requested ∩ allowed.
amp_token() {
  curl -sf -u amp-api-client:amp-api-client-secret -d grant_type=client_credentials \
    --data-urlencode 'scope=amp:project:read amp:agent:create amp:agent:read amp:agent:build amp:agent:update amp:agent:deploy amp:agent:env-non-production amp:llm-provider:create amp:llm-provider:read amp:llm-provider:deploy amp:mcp-server:create amp:mcp-server:read amp:mcp-server:update amp:mcp-server:connect amp:mcp-server:api-key-manage amp:agent:api-key-manage amp:gateway:read amp:environment:read' \
    http://thunder.amp.localhost:8080/oauth2/token | jq -r .access_token
}

# idp_token -> admin token for the environment ThunderID (its AMP system client).
idp_token() {
  local secret
  secret=$(kubectl -n amp-thunder-default-default get secret amp-thunder-default-default-system-client \
    -o jsonpath='{.data.client-secret}' | base64 -d)
  curl -sf -u "amp-system-client:$secret" -d grant_type=client_credentials -d scope=system \
    --data-urlencode "resource=$IDP/mcp" "$IDP/oauth2/token" | jq -r .access_token
}

# call <token> <method> <url> [json] -> REST call; prints the body, fails with it on HTTP >= 400
call() {
  local out
  out=$(curl -s --fail-with-body -X "$2" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    "$3" ${4:+-d "$4"}) || { warn "$2 $3 failed"; echo "$out" >&2; return 1; }
  printf '%s' "$out"
}

# wait_for_build <token> <agent> -> waits for the agent's newest build to finish (deploys it)
wait_for_build() {
  local build status start=$SECONDS
  while :; do
    # A build loads the VM heavily, and the platform's API can briefly fail (its ThunderID
    # restarts under memory pressure); a failed poll is retried rather than fatal.
    build=$(call "$(amp_token)" GET "$AMP_API/projects/$AMP_PROJECT/agents/$2/builds" 2>/dev/null \
      | jq -c '.builds | sort_by(.startedAt) | last // {}') || { sleep 15; continue; }
    status=$(jq -r '.status // "Pending"' <<<"$build")
    case "$status" in
      Completed) log "Build $(jq -r .buildName <<<"$build") completed"; return ;;
      Failed) die "Build $(jq -r .buildName <<<"$build") of '$2' failed. See its Builds tab in the console." ;;
    esac
    (( SECONDS - start > 1800 )) && die "Timed out waiting for the build of '$2' (last status: $status)"
    sleep 15
  done
}

# allow_qdrant <component> -> lets the component's sandboxed pods reach Qdrant (extra NetworkPolicy)
allow_qdrant() {
  local ns="" _
  for _ in $(seq 30); do
    ns=$(kubectl get pods -A -l "openchoreo.dev/component=$1" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
    [[ -n "$ns" ]] && break
    sleep 5
  done
  [[ -n "$ns" ]] || die "No pod for '$1' found; is its deployment running?"
  sed -e "s/AGENT_NAMESPACE/$ns/" -e "s/COMPONENT/$1/g" "$HERE/values/agent-egress-qdrant.yaml" | kubectl apply -f - >/dev/null
}
