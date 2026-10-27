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
