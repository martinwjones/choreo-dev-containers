# API Manager 4.5 with APK as the Gateway

Runs **WSO2 API Manager 4.5.0** as the control plane and **WSO2 APK 1.3.0** (Kubernetes-native,
Envoy-based) as the gateway, connected by the **APK agent**. APIs designed and published in APIM
are pushed to APK, which serves them on its own gateway.

Based on the upstream guide:
[APK as a Gateway in API Manager](https://apk.docs.wso2.com/en/latest/control-plane/apk-as-gateway-in-apim/apk-as-gateway-in-apim-qsg/).

```
Browser ──443──> NGINX ingress ──> APIM Publisher / Devportal / Admin (am.wso2.com)
                                        │  APIs, apps, subscriptions
                                        ▼
                                   APK agent ──> APK custom resources
                                                        │
curl ──9095──> APK gateway (default.gw.wso2.com) ───────┘──> backend
```

## Before you start

- Open the repo in its Dev Container (see the [main README](../../../README.md)).
- Give Docker at least **6 GB of memory** (8 GB recommended) and 4 CPUs. This scenario uses ~3 GB.
- Ports **80, 443 and 9095** must be free on your machine.
- Only one scenario fits in an 8 GB Docker VM at a time. If Agent Manager is running, stop it:
  `k3d cluster stop amp-local`.
- To open the portals from your host browser, add this line to the host's `/etc/hosts`
  (`C:\Windows\System32\drivers\etc\hosts` on Windows). Inside the container it is set up for you.
  ```
  127.0.0.1 am.wso2.com api.am.wso2.com idp.am.wso2.com default.gw.wso2.com
  ```

## Run it

```bash
bash tutorials/01-api-manager/apk-gateway/install.sh    # ~10-15 min on first run
bash tutorials/01-api-manager/apk-gateway/populate.sh   # sample API, app and token; calls the API
```

`install.sh` installs, in order, into the `apk` namespace of the `wso2-cluster` k3d cluster:

1. APK gateway (`wso2apk/apk-helm` 1.3.0-1)
2. API Manager control plane (`wso2apim/wso2am-acp` 4.5.0-1)
3. APK agent (`wso2apkagent/apim-apk-agent` 1.3.0)

`populate.sh` then does the Publisher and Devportal steps of the guide through the REST APIs:

- Imports `SampleService` 0.1.0 (context `/sample-api`) from an OpenAPI definition,
  deploys it to the APK gateway and publishes it.
- Creates the application `SampleServiceApp`, subscribes it, generates production keys and
  an access token.
- Calls `GET https://default.gw.wso2.com:9095/sample-api/0.1.0/uuid` and expects HTTP 200.

Both scripts are safe to re-run, for example after a disconnect or a container rebuild.

## Use it

| What | Where | Login |
| :--- | :--- | :--- |
| Publisher | https://am.wso2.com/publisher | `admin` / `admin` |
| Devportal | https://am.wso2.com/devportal | `admin` / `admin` |
| Admin portal | https://am.wso2.com/admin | `admin` / `admin` |
| APK gateway | https://default.gw.wso2.com:9095 | access token |

Certificates are self-signed, so accept the browser warning (or use `curl -k`).

Call the sample API again with the token saved by `populate.sh` (valid for one hour; re-run
`populate.sh` for a new one):

```bash
curl -k https://default.gw.wso2.com:9095/sample-api/0.1.0/uuid \
  -H "Authorization: Bearer $(cat tutorials/01-api-manager/apk-gateway/.state/access-token)"
```

To publish your own API, create it in the Publisher with **APK** as the gateway type, deploy a
revision to the `Default` environment, publish it, then subscribe from the Devportal. The APK
agent picks it up within about 30 seconds.

## Add API Manager's own gateway (WebSocket and other streaming APIs)

APK 1.3 only serves REST, GraphQL and gRPC APIs. For **WebSocket**, WebSub and SSE APIs, add API
Manager's own gateway (the 4.5.0 "universal gateway"). It serves the control plane's second
gateway environment, **`Default_synapse`**, next to APK's `Default`:

```bash
bash tutorials/01-api-manager/apk-gateway/install-gateway.sh    # ~5 min, ~1.5 GB more memory
```

It also deploys WSO2's sample WebSocket chat backend used by the
[Create and Publish a WebSocket API](https://apim.docs.wso2.com/en/latest/tutorials/streaming-api/create-and-publish-websocket-api/)
guide. When following that guide in this lab:

| Guide says | Use in this lab |
| :--- | :--- |
| Endpoint `ws://localhost:8080` (and starting the sample with `npm start`) | `ws://websocket-backend.samples.svc.cluster.local:8080` (already running) |
| Topic URL mappings (`/notifications`, `/rooms?room={uri.var.roomID}`) | Same. Without a URL mapping the gateway connects to the backend's `/`, and no messages arrive |
| Gateway environment | Deploy the revision to **`Default_synapse`**, not `Default` (APK can't run WebSocket APIs) |
| Invoke `ws://localhost:9099/<context>/<version>/<topic>` | `wss://websocket.wso2.com/<context>/<version>/<topic>` (port 443, TLS, through the ingress), with header `Authorization: Bearer <token>` |

On the Mac, add `127.0.0.1 gw.wso2.com websocket.wso2.com` to `/etc/hosts` (the dev container
gets it automatically). The certificate is self-signed: with `wscat`, add `-n`.

What `install-gateway.sh` sets (see [values/apim-gateway-overrides.yaml](values/apim-gateway-overrides.yaml)):

- **Connection to the control plane:** key manager, throttling and event hub point at release
  `apim`'s services; the event hub is enabled so the gateway hears about deployments.
- **Service name `wso2am-gateway-service`:** what the control plane's `Default_synapse`
  environment calls.
- **Keystores:** the chart always mounts the secret `apim-keystore-secret`; the script creates it
  from the control plane's own default keystores, so the gateway trusts its tokens.
- **Database and admin:** the chart leaves the shared database blank ("Cannot initialize the
  realm"); it uses the image's embedded H2, like the control plane, with admin `admin`/`admin`.
- **Upstream chart bug fixed:** the key manager URL renders without a port unless
  `km.servicePort` is set.
- One replica with 1 GB JVM heap, instead of two with 2-3 GB each.

### The Pizza Shack sample API

The Publisher's **Pizza Shack** sample points at `https://am.wso2.com/am/sample/pizzashack/v1/api`,
a backend bundled only in the all-in-one API Manager. This lab's control plane and gateways
don't include it, so calls fail with HTTP 500 "Error connecting to the back end".
`install-gateway.sh` deploys a mock of it ([samples/pizzashack-backend.yaml](samples/pizzashack-backend.yaml):
menu, place/get/update/delete orders). Set the API's production and sandbox endpoints to

```
http://pizzashack-backend.samples.svc.cluster.local:8080/am/sample/pizzashack/v1/api
```

and deploy a new revision to `Default_synapse`. (Done for the current PizzaShack API on
2026-11-16; a newly created sample API needs it again.)

**Calling it from the Developer Portal's Try Out:** the browser calls `https://gw.wso2.com`
directly, so the Mac needs `gw.wso2.com` in `/etc/hosts` and the browser must have accepted
that host's self-signed certificate (open https://gw.wso2.com once and click through the
warning). Otherwise the browser reports a CORS / network failure even though CORS is fine.

## Developer Portal application sharing

Application sharing is on (`[apim.devportal] enable_application_sharing = true`, set by
`enableApplicationSharing` in [values/apim-acp-overrides.yaml](values/apim-acp-overrides.yaml)):
Developer Portal applications are shared between users of the same organization.

To change any API Manager setting, edit `values/apim-acp-overrides.yaml` (the chart writes
`deployment.toml` from it; editing the file inside the pod is lost on restart) and re-run
`install.sh`, keeping the next section in mind.

## API Manager's data is not persistent

API Manager stores everything (APIs, applications, subscriptions, users) in the H2 database
inside its pod. **Anything that replaces the pod wipes it:** a `helm upgrade` of `apim` (such
as a config change via `install.sh`), deleting the pod, or a reinstall. (Stopping and starting
the cluster has kept it so far.) To keep your work, export the APIs first and import them after:

```bash
# Before: export every API (Publisher REST API, same as apictl export)
#   GET  /api/am/publisher/v4/apis/export?apiId=<id>&format=YAML&preserveStatus=true
# After:  import, then deploy a new revision to the original gateway environment
#   POST /api/am/publisher/v4/apis/import?preserveProvider=true  (multipart: file=@<api>.zip)
```

Exports don't include deployments, applications or subscriptions; redeploy and resubscribe.

## Check it

```bash
kubectl get pods -n apk
kubectl get apis.dp.wso2.com,applications.cp.wso2.com,subscriptions.cp.wso2.com -n apk
```

## Pause, resume, remove

```bash
k3d cluster stop wso2-cluster       # pause; everything stays installed
k3d cluster start wso2-cluster      # resume (APIM takes a few minutes to answer again)
bash tutorials/01-api-manager/apk-gateway/uninstall.sh   # remove the scenario, keep the cluster
```

## What differs from the upstream guide

Upstream Helm values are kept unchanged in [values/upstream/](values/upstream/); our changes are in
the `values/*-overrides.yaml` files, each with a comment explaining why:

- **APIM image:** the upstream sample points at a release-candidate image that no longer exists,
  so we use the official multi-arch `wso2/wso2am-acp:4.5.0` (works on Apple Silicon).
- **Memory:** APIM's memory is trimmed and its startup probe relaxed to fit a laptop.
- **APK IdP off:** APK's own IdP and PostgreSQL are disabled, because APIM is the key manager.
  Saves ~1 GB.
- **Redis image:** Bitnami removed its free images in 2025, so APK's Redis comes from `bitnamilegacy`.
- **Install order:** components are installed one at a time instead of in parallel.
- **Versions:** Helm must be 3.x (Helm 4 fails on the APK chart), and Kubernetes is pinned to 1.32,
  the newest APK 1.3 supports. The Dev Container already provides both.

## Troubleshooting

- **A pod is stuck in `Pending` or keeps restarting:** usually memory. Check `kubectl top nodes`
  and make sure the `amp-local` cluster is stopped.
- **The portal redirects to a URL with a random port:** the host is reaching 443 through VS Code
  port forwarding instead of the Docker-published port. Rebuild the Dev Container and make sure
  nothing else on the host uses 443.
- **A Helm release is stuck `pending-install` / `pending-upgrade`:** just re-run `install.sh`; it
  rolls the release back first.
- **`populate.sh` gets 404 or 401 from the gateway:** the agent may still be syncing. Wait 30 seconds
  and re-run it.
