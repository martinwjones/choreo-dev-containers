# Practical Exercise: Getting Started with WSO2 API Manager

> **In this lab** API Manager 4.7.0 runs in the `wso2-cluster` k3d cluster via the official
> Helm chart instead of a local zip install. The training steps below are kept as written;
> [Running this unit in the lab](#running-this-unit-in-the-lab) at the end shows how each
> one maps onto the cluster.

## Training Objective

Verify that the products required for running this tutorial are installed and configured. and
deploy and test the data required to work with the sample.
Note: The participants are expected to be connected to the internet throughout in order to
successfully complete the lab exercises.

### Business Scenario

PizzaShack Limited wants to extend their website for placing and managing online orders
as a part of their effort in becoming the #1 online pizza shop. They have also found it
increasingly useful to build an application for smartphones. The application is a web
application allowing you to choose and buy a pizza online. They have subcontracted the
development of the smartphone application to FunkyApps LLC. John Doe, Chief Architect
of FunkyApps had some interesting feedback for PizzaShack. He suggested that the
company considers monitoring of consumer statistics and probably looking into complex
event processing in the future. John also suggested that they make use of an API Store
backed by a modern API Gateway providing security features such as OAuth 2.0 access
tokens.
In order to achieve this, PizzaShack will be using WSO2 API Manager and a number of
other WSO2 products for monitoring statistics, single sign-on, and so on.
The application leverages an API with 3 resources, which are exposed via the API
Manager. Corresponding services are hosted in the WSO2 API Manager. WSO2 API
Manager offers Analytics as a Cloud Service. This will be used for monitoring.

#### High-Level Steps

* Install WSO2 API Manager
* Configure API Manager Analytics
* Other installations
* Overview of the key directories in WSO2 API Manager
* Key configuration files
* Configure port offsets

### Detailed Instructions

**Install WSO2 API Manager**
Before installing the product, ensure that the installation prerequisites have been met.
Refer to the documentation [1] for detailed instructions. If prerequisites are fulfilled,
instructions on installing the product can be found for Linux, OS X or Windows at [2].

1. [Installation Prerequisites](https://apim.docs.wso2.com/en/4.7.0/install-and-setup/install/installation-prerequisites/)
2. [Installing the product](https://apim.docs.wso2.com/en/4.7.0/install-and-setup/install/installing-the-product/installing-api-m-runtime/)

**Configure Moesif Analytics**
Refer to the documentation [1] for detailed instructions.
[1] [Moesif analytics Integration](https://apim.docs.wso2.com/en/4.7.0/monitoring/api-analytics/moesif-analytics/moesif-integration-guide/)

**Other Installations**
In order to complete the use case described in this lab kit the following products must be
installed: A REST API client or cURL [1], CLI tool [2] (Dev-Ops Tooling)

1. <https://www.getpostman.com/apps>
2. <https://wso2.com/api-management/tooling/>

For MAC OS X
Installing brew [1], JDBC driver for MySQL[2] and cURL[3]

1. Install brew from <https://brew.sh/>
2. In the terminal run
    * `brew tap gbeine/homebrew-java`
    * `brew install mysql-connector-java`
3. In terminal run `brew install curl`

For Windows
Installing JDBC Drivers for SQL[1]

1. Install Drivers from this location
2. Install cURL from this location

### Overview of the Key Directories in WSO2 API Manager

The structure of the `<APIM_HOME>` folder is as follows.
`/backup`
`/bin` - This folder contains all the executable files including those scripts that are used to start/stop the application on Linux and Windows environments e.g., api-manager.sh and api-manager.bat.
`/dbscripts` – A collection of database scripts required to create the Carbon database and the API Manager specific database on a variety of database management systems.
`/lib` –The lib directory houses all the jar files that will be converted to OSGi bundles at startup and copied to the dropins directory.
`/repository` – The main repository for all kinds of deployments and configurations in Carbon. This includes all default services, created APIs, Carbon configurations etc.
`/resources` – Contains additional resources that may be used by the API-M.
`/samples`  - Sample APIs that can be used to explore the WSO2 API  Manager functionality.
`/solr`
`/tmp` – Will contain temporary files that are created when a product is run. These files will be cleared from time to time based on housekeeping tasks.
`/updates`
INSTALL.txt
LICENSE.txt
README.txt
release-notes.html
wso2carbon.pid
XMLInputFactory.properties

#### Key Configuration Files

| File | Description |
| :--- | :---: |
| `<PRODUCT_HOME>`/repository/conf/deployment.toml | The main configuration file. |
| `<PRODUCT_HOME>`/repository/conf/log4j2.properties | The log4j2 configuration file used by WSO2 Carbon. |

**Configure Port Offset**
When you run multiple WSO2 products, multiple instances of the same product, or
multiple WSO2 product clusters on the same server or virtual machines (VMs), you must
change their default ports with an offset value to avoid port conflicts. The default HTTP
and HTTPS ports (without offset) of a WSO2 product are 9763 and 9443, respectively.
Port offset defines the number by which all ports defined in the runtime such as the
HTTP/S ports will be changed. For example, if the default HTTP port is 9763 and the port
offset is 1, the effective HTTP port will change to 9764. For each additional WSO2 product
instance, you set the port offset to a unique value. The default port offset is 0.
There are two ways to set an offset to a port:

* Pass the port offset to the server during startup. The following command starts the
server with the default port incremented by 3 : `/api-manager.sh -DportOffset=3`
* Set the Ports section of `<PRODUCT_HOME>/repository/conf/deployment.toml` as
follows:

```toml
    [server]
    offset=3
```

We will be using API-M and APIM Analytics for these exercises. APIM will run locally and
API Manager Analytics will be delivered via Moesif Analytics.

| File | Port Offset |
| :--- | :---: |
| `<API-M_HOME>`/repository/conf/deployment.toml | 0 |

Follow the documentation [1] to run WSO2 API Manager.
[1] [Documentation: Running the Product](https://apim.docs.wso2.com/en/4.7.0/install-and-setup/install/installing-the-product/running-the-api-m/)
Expected Outcome
As the API-M was not given an offset, it will run on the default port.

---

## Running this unit in the lab

Deploys **WSO2 API Manager 4.7.0, all-in-one** (Publisher, Devportal, Admin, Key Manager,
Traffic Manager and Gateway in one pod) into the `apim` namespace of the `wso2-cluster`
k3d cluster, with the official chart `wso2am-all-in-one` 4.7.0-1 from
[wso2/helm-apim](https://github.com/wso2/helm-apim).

```
Browser ──443──> NGINX ingress ──am.wso2.com──> APIM :9443  (Publisher, Devportal, Admin, Carbon)
curl    ──443──> NGINX ingress ──gw.wso2.com──> APIM :8243  (API Gateway)
                                                  │
                                                  └──> Moesif (api.moesif.net), when configured
```

### Before you start

- Open the repo in its Dev Container (see the [main README](../../README.md)).
- APIM needs about **2–3 GB** of memory. Stop Agent Manager if it is running:
  `k3d cluster stop amp-local`.
- Tutorial 01 also serves APIM on `https://am.wso2.com`, so remove it first:
  `bash tutorials/01-api-manager/apk-gateway/uninstall.sh` (`install.sh` checks this).
- To open the portals from your host browser, add this line to the host's `/etc/hosts`
  (inside the container `install.sh` adds it for you):
  ```
  127.0.0.1 am.wso2.com gw.wso2.com
  ```
- For Moesif analytics: a Moesif account and its **Application ID** (shown in Moesif's
  API keys / installation settings; see the Moesif integration guide linked below).

### Install WSO2 API Manager

```bash
# first time, with Moesif (the ID is saved to .state/moesif-app-id and reused):
MOESIF_APP_ID=<your-moesif-application-id> bash tutorials/03-api-manager-fundamentals/install.sh
# later runs, or without Moesif:
bash tutorials/03-api-manager-fundamentals/install.sh
```

The first run pulls the ~1 GB image and takes 5–10 minutes; APIM itself needs 3–6 minutes
to start. The script is safe to re-run.

| What | Where | Login |
| :--- | :--- | :--- |
| Publisher | https://am.wso2.com/publisher | `admin` / `admin` |
| Devportal | https://am.wso2.com/devportal | `admin` / `admin` |
| Admin portal | https://am.wso2.com/admin | `admin` / `admin` |
| Carbon console | https://am.wso2.com/carbon | `admin` / `admin` |
| API Gateway | https://gw.wso2.com | access token |

Certificates are self-signed, so accept the browser warning (or use `curl -k`).

### Configure Moesif analytics

The chart writes the Moesif settings into `deployment.toml` (the same thing the
[Moesif integration guide](https://apim.docs.wso2.com/en/4.7.0/monitoring/api-analytics/moesif-analytics/moesif-integration-guide/)
asks you to add by hand):

```toml
[apim.analytics]
enable = true
type = "moesif"
[apim.analytics.properties]
moesifKey = "<Moesif Application ID>"
moesif_base_url = "https://api.moesif.net"
send_headers = false
```

To add, change or remove the ID later, update `.state/moesif-app-id` (or pass
`MOESIF_APP_ID=...`) and re-run `install.sh`; the pod restarts with the new configuration.
Without an ID, analytics is disabled. Events show up in Moesif once APIs are called
through the gateway (later units).

### Key directories and configuration files

The container image has the same `<APIM_HOME>` layout as the zip
(under `/home/wso2carbon`; the path is in `$WSO2_SERVER_HOME`). To look around it:

```bash
bash tutorials/03-api-manager-fundamentals/explore.sh
```

It lists `<APIM_HOME>`, shows `repository/conf/deployment.toml` and `log4j2.properties`,
the `[server]` section (hostname, offset), the analytics section (with the key hidden), the
ports the server reported at startup and the Kubernetes service ports. For a shell:

```bash
kubectl exec -it -n apim deploy/apim-wso2am-all-in-one-am-deployment-1 -- bash
```

`deployment.toml` is generated by the chart from a ConfigMap on every start, so edits made
inside the pod are lost on restart. Make lasting changes through
[values/apim-overrides.yaml](values/apim-overrides.yaml) and re-run `install.sh`.

### Configure port offset

The chart's `wso2.apim.portOffset` value sets `[server] offset` in `deployment.toml` and
shifts the pod and service ports. `install.sh` passes `PORT_OFFSET` through to it:

```bash
PORT_OFFSET=3 bash tutorials/03-api-manager-fundamentals/install.sh   # try an offset
bash tutorials/03-api-manager-fundamentals/explore.sh                  # ports now 9446, 8246, ...
bash tutorials/03-api-manager-fundamentals/install.sh                  # back to offset 0
```

> **Not yet tried in this lab.** The chart's ingress always targets ports 9443 and 8243, so
> `https://am.wso2.com` stops working while an offset is set. Use
> `kubectl port-forward -n apim svc/apim-wso2am-all-in-one-am-service 9446:9446` and
> https://localhost:9446/carbon instead. The chart also writes the shifted port into
> `[transport.https]`. If Carbon adds the offset on top of that, the server listens on
> 9449 and the startup probe (9446) fails. Check `explore.sh` and the pod logs.

The expected outcome of the unit is offset **0**: APIM runs on the default ports
(9443 HTTPS, 9763 HTTP, 8243/8280 gateway).

### Other installations

The dev container already has `curl`. Postman and the `apictl` CLI are optional and run
on your host. The MySQL JDBC driver is not needed: this lab uses the embedded H2 databases.

### Check, pause, remove

```bash
kubectl get pods,svc,ingress -n apim
kubectl logs -n apim deploy/apim-wso2am-all-in-one-am-deployment-1 | tail -50

k3d cluster stop wso2-cluster        # pause; APIM data is lost (H2 inside the pod)
k3d cluster start wso2-cluster       # resume; APIM takes a few minutes to answer again
bash tutorials/03-api-manager-fundamentals/uninstall.sh   # remove; keeps .state/ and the cluster
```

### What differs from the training / upstream chart

Upstream chart values are kept unchanged in [values/upstream/](values/upstream/); our changes
are in [values/apim-overrides.yaml](values/apim-overrides.yaml), each with a comment:

- **Kubernetes instead of a zip**: same product and `<APIM_HOME>` layout, but started by the
  container entrypoint instead of `bin/api-manager.sh`, and configured through Helm values.
- **Ingress instead of Gateway API**: the chart defaults to Gateway API routes; this lab uses
  the NGINX ingress (`am.wso2.com`, `gw.wso2.com`). WebSocket/WebSub ingresses are off.
- **Embedded H2 databases** (the chart expects an external RDBMS). Data does not survive a
  pod restart.
- **Image**: the chart has no default; we pin the official multi-arch `wso2/wso2am:4.7.0`
  by digest.
- **Encryption key**: APIM 4.7 requires a symmetric encryption key. `install.sh` generates
  one into `.state/encryption-key` on first run and reuses it.
- **Resources**: CPU request lowered from 2 to 0.5, initial heap from 2 GB to 1 GB, startup
  probe relaxed (first start on a laptop takes 3–6 minutes).
- **Chart download**: the chart release's `index.yaml` uses relative URLs that 404, so
  `helm repo add` does not work. `install.sh` downloads the `.tgz` into `.state/` and checks
  its SHA-256.

### Troubleshooting

- **Pod `Pending` or restarting:** usually memory. Check `kubectl top nodes`; make sure
  `amp-local` is stopped.
- **`install.sh` says tutorial 01 is installed:** both serve `am.wso2.com`; uninstall tutorial 01.
- **Portal returns 503 / 404 after a while:** the pod restarted and is still starting; watch
  `kubectl get pods -n apim -w`.
- **No data in Moesif:** check that `explore.sh` shows `type = "moesif"` and
  `moesifKey = <set, hidden>`, and that the gateway has served API calls. Moesif can take a
  minute to show events.
- **Helm release stuck `pending-*`:** re-run `install.sh`; it rolls the release back first.
