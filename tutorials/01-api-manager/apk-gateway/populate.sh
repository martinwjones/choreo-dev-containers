#!/bin/bash
# Populates the scenario with sample data through the APIM REST APIs
# (the Publisher/Devportal steps of the quick start guide):
#   API "SampleService" -> deployed to the APK gateway -> published
#   App "SampleServiceApp" -> subscribed -> production keys -> access token
# Then calls the API through APK. Safe to re-run: existing objects are reused.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../../scripts/lib.sh"
use_cluster "$CLUSTER_NAME"

AM=https://am.wso2.com
GW=https://default.gw.wso2.com:9095
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"
PUB=$AM/api/am/publisher/v4
DEV=$AM/api/am/devportal/v3

API_NAME=SampleService
API_CONTEXT=/sample-api
API_VERSION=0.1.0
API_BACKEND=https://dev-tools.wso2.com/gs/helpers/v1.0
OAS_URL=https://raw.githubusercontent.com/wso2/docs-apk/refs/heads/1.3.0/en/docs/assets/files/get-started/SampleAPIDefinition.json
APP_NAME=SampleServiceApp
GATEWAY_ENV=Default

STATE_DIR="$HERE/.state"
mkdir -p "$STATE_DIR"

# api <curl args...> -> authenticated REST call; prints the error body and fails on HTTP >= 400
api() {
  local out
  out=$(curl -sk --fail-with-body -H "Authorization: Bearer $TOKEN" "$@") \
    || { warn "REST call failed: $*"; echo "$out" >&2; return 1; }
  printf '%s' "$out"
}

log "Registering a REST API client and getting an admin token"
REG=$(curl -sk --fail-with-body -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' \
  "$AM/client-registration/v0.17/register" \
  -d '{"clientName":"lab_populate","owner":"'"$ADMIN_USER"'","grantType":"password refresh_token","saasApp":true}')
CK=$(jq -r .clientId <<<"$REG"); CS=$(jq -r .clientSecret <<<"$REG")
TOKEN=$(curl -sk --fail-with-body -u "$CK:$CS" "$AM/oauth2/token" \
  -d grant_type=password -d "username=$ADMIN_USER" -d "password=$ADMIN_PASS" \
  --data-urlencode "scope=apim:api_view apim:api_create apim:api_publish apim:api_manage apim:subscribe apim:app_manage apim:sub_manage" \
  | jq -r .access_token)

# --- Publisher ---------------------------------------------------------------
API_ID=$(api "$PUB/apis?query=name:$API_NAME%20version:$API_VERSION" | jq -r '.list[0].id // empty')
if [[ -z "$API_ID" ]]; then
  log "Importing OpenAPI definition as $API_NAME $API_VERSION (APK gateway)"
  PROPS=$(jq -nc --arg n "$API_NAME" --arg c "$API_CONTEXT" --arg v "$API_VERSION" --arg b "$API_BACKEND" '{
    name: $n, context: $c, version: $v, gatewayType: "wso2/apk", policies: ["Unlimited"],
    endpointConfig: {endpoint_type: "http", production_endpoints: {url: $b}, sandbox_endpoints: {url: $b}}}')
  API_ID=$(api -X POST "$PUB/apis/import-openapi" -F "url=$OAS_URL" -F "additionalProperties=$PROPS" | jq -r .id)
else
  log "API $API_NAME already exists ($API_ID)"
fi

if [[ $(api "$PUB/apis/$API_ID/deployments" | jq 'length') == 0 ]]; then
  log "Creating a revision and deploying it to the '$GATEWAY_ENV' (APK) gateway"
  VHOST=$(api "$PUB/settings" | jq -r --arg e "$GATEWAY_ENV" '.environment[] | select(.name==$e) | .vhosts[0].host')
  REV_ID=$(api -X POST -H 'Content-Type: application/json' "$PUB/apis/$API_ID/revisions" \
    -d '{"description":"Initial revision (populate.sh)"}' | jq -r .id)
  api -X POST -H 'Content-Type: application/json' "$PUB/apis/$API_ID/deploy-revision?revisionId=$REV_ID" \
    -d '[{"name":"'"$GATEWAY_ENV"'","vhost":"'"$VHOST"'","displayOnDevportal":true}]' >/dev/null
fi

if [[ $(api "$PUB/apis/$API_ID" | jq -r .lifeCycleStatus) != PUBLISHED ]]; then
  log "Publishing $API_NAME"
  api -X POST "$PUB/apis/change-lifecycle?apiId=$API_ID&action=Publish" >/dev/null
fi

# --- Devportal ---------------------------------------------------------------
APP_ID=$(api "$DEV/applications?query=$APP_NAME" | jq -r --arg n "$APP_NAME" '.list[] | select(.name==$n) | .applicationId' | head -1)
if [[ -z "$APP_ID" ]]; then
  log "Creating application $APP_NAME"
  APP_ID=$(api -X POST -H 'Content-Type: application/json' "$DEV/applications" \
    -d '{"name":"'"$APP_NAME"'","throttlingPolicy":"10PerMin","description":"Sample Service Application","tokenType":"JWT"}' \
    | jq -r .applicationId)
fi

if [[ $(api "$DEV/subscriptions?applicationId=$APP_ID&apiId=$API_ID" | jq '.count') == 0 ]]; then
  log "Subscribing $APP_NAME to $API_NAME"
  api -X POST -H 'Content-Type: application/json' "$DEV/subscriptions" \
    -d '{"applicationId":"'"$APP_ID"'","apiId":"'"$API_ID"'","throttlingPolicy":"Unlimited"}' >/dev/null
fi

KEY_MAPPING=$(api "$DEV/applications/$APP_ID/oauth-keys" | jq -r '.list[] | select(.keyType=="PRODUCTION") | .keyMappingId' | head -1)
if [[ -z "$KEY_MAPPING" ]]; then
  log "Generating production keys"
  KEY_MAPPING=$(api -X POST -H 'Content-Type: application/json' "$DEV/applications/$APP_ID/generate-keys" \
    -d '{"keyType":"PRODUCTION","keyManager":"Resident Key Manager","grantTypesToBeSupported":["client_credentials"],"validityTime":3600}' \
    | jq -r .keyMappingId)
fi

ACCESS_TOKEN=$(api -X POST -H 'Content-Type: application/json' \
  "$DEV/applications/$APP_ID/oauth-keys/$KEY_MAPPING/generate-token" \
  -d '{"validityPeriod":3600,"scopes":[]}' | jq -r .accessToken)
echo "$ACCESS_TOKEN" > "$STATE_DIR/access-token"

# --- Verify on the data plane -------------------------------------------------
log "Calling the API through APK (the agent can take ~30s to sync)"
URL="$GW$API_CONTEXT/$API_VERSION/uuid"
for i in $(seq 1 12); do
  CODE=$(curl -sk -o "$STATE_DIR/last-response" -w '%{http_code}' -H "Authorization: Bearer $ACCESS_TOKEN" "$URL")
  [[ "$CODE" == 200 ]] && break
  sleep 10
done
echo "GET $URL -> HTTP $CODE"; cat "$STATE_DIR/last-response"; echo
[[ "$CODE" == 200 ]] || die "API call did not succeed"

log "Custom resources the APK agent created from APIM:"
kubectl get apis.dp.wso2.com,applications.cp.wso2.com,subscriptions.cp.wso2.com -n apk 2>/dev/null | grep -v apk-system

cat <<EOF

Access token saved to $(realpath --relative-to="$PWD" "$STATE_DIR/access-token") (valid 1 hour). Try:
  curl -k "$URL" -H "Authorization: Bearer \$(cat $(realpath --relative-to="$PWD" "$STATE_DIR/access-token"))"
EOF
