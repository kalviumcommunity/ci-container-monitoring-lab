# ci-container-monitoring-lab

A small, fully local DevOps stack that wires a single commit all the way to a
running, monitored service:

**commit → CI → container → deploy → dashboard**

The stack contains:

- **app/** — a Node.js + Express service exposing `/`, `/health`, `/metrics` and `/work`
- **Dockerfile** — builds the service image
- **docker-compose.yml** — runs the app, Prometheus and Grafana together
- **prometheus/** — Prometheus scrape configuration
- **grafana/** — provisioned datasource and a "Service Overview" dashboard
- **.github/workflows/ci.yml** — GitHub Actions pipeline (install, test, build, smoke test)

Everything runs locally and for free. No cloud account or billing is required.

## Prerequisites

- Docker + Docker Compose
- Node.js 18+ (only needed if you want to run tests outside a container)
- `git`, `curl`

## Run the stack

```bash
docker compose up -d          # build + start app, Prometheus, Grafana
docker compose ps             # show container status and health
docker compose logs -f app    # follow the application logs
```

Services once up:

| Service     | URL                      |
|-------------|--------------------------|
| App         | http://localhost:8080    |
| Prometheus  | http://localhost:9090    |
| Grafana     | http://localhost:3000    |

Grafana logs in anonymously (admin/admin also works). Open the **Service
Overview** dashboard under the **Lab** folder.

Tear down:

```bash
docker compose down
```

## Verify the service

```bash
curl localhost:8080/health     # -> {"status":"ok"}
curl localhost:8080/           # -> service metadata
curl localhost:8080/metrics    # -> Prometheus metrics
```

Check the Prometheus scrape target:

```
http://localhost:9090/targets   # the app target should be UP
```

## Generate sample traffic

```bash
./scripts/generate-traffic.sh                       # defaults to localhost:8080
./scripts/generate-traffic.sh http://localhost:8080 500
```

Then watch the panels in the Grafana **Service Overview** dashboard update.

## Run the tests locally

```bash
cd app
npm install
npm test
```

## GitHub Actions

The workflow in `.github/workflows/ci.yml` runs automatically on every push and
pull request. It installs dependencies, runs the unit tests, builds the Docker
image and smoke-tests the running container. Watch it under the **Actions** tab
of your fork, or trigger it by pushing a commit / opening a PR.

## Rollback

Releases are tagged in Git. You can inspect history with:

```bash
git log --oneline
git tag
```

To roll a bad release back to a previous version, either revert the offending
commit and redeploy, or rebuild from a previous tag:

```bash
git revert <commit>          # revert a bad release
docker compose up -d --build # redeploy the reverted version
```

## Cloud Deployment Mapping

A mapping of this local DevOps flow to an equivalent production deployment on Google Cloud Platform (GCP):

| Local Stack Component | Cloud Equivalent (GCP) | Description & Implementation Details |
|---|---|---|
| **Local Docker Build** (`Dockerfile`) | **Google Artifact Registry (GAR)** | Build and push the container image to `us-docker.pkg.dev/$PROJECT_ID/repo/image:$COMMIT_SHA` via GitHub Actions or Cloud Build. |
| **Docker Compose Deploy** (`docker-compose.yml`) | **Google Cloud Run** | Deploy serverless container services using `gcloud run deploy --image ... --port 3000 --min-instances 1`. Configure HTTP liveness/readiness probes targeting `/health`. |
| **Prometheus Scraping** (`prometheus.yml`) | **Google Cloud Managed Service for Prometheus (GMP)** / OpenTelemetry Collector | Scrapes the `/metrics` endpoint using Managed Service for Prometheus PodMonitoring / Sidecar agent, or exports telemetry via OpenTelemetry Collector. |
| **Grafana Dashboards** (`service-overview.json`) | **Google Cloud Monitoring Dashboards** | Custom dashboards configured with MQL/PromQL metrics (e.g. `http_requests_total`, p95 `http_request_duration_seconds`), accompanied by Alerting Policies for 5xx error spikes or latency breaches. |
| **Local Rollback** (`git revert`) | **Cloud Run Revisions & Traffic Splitting** | Instant zero-downtime rollback by shifting 100% traffic back to the previous healthy revision: `gcloud run services update-traffic <service> --to-revisions=<PREV_REVISION>=100`. |

