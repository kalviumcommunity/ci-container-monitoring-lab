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

## Cloud Release Mapping

This section maps the local DevOps pipeline (**commit → CI → container → deploy → dashboard**) to its equivalent production deployment on Google Cloud Platform (GCP).

| Local Component / Action | Cloud Equivalent | Implementation & Workflow Details |
|---|---|---|
| **Source Control & CI** (`.github/workflows/ci.yml`) | **GitHub Actions / Cloud Build** | Executes automated linting, unit testing (`npm test`), and container build steps on every push/PR. |
| **Container Image Registry** (`docker build`) | **Google Artifact Registry** (`pkg.dev`) | Container images are built and pushed with immutable tag versions (e.g., `us-docker.pkg.dev/project/repo/app:${GITHUB_SHA}`). |
| **Service Deployment** (`docker compose up`) | **Google Cloud Run** | Deploys containers serverlessly with environment variables (`MAINTENANCE_MODE=off`), HTTPS ingress, and liveness/readiness health probes (`/health`). |
| **Metrics Collection** (`Prometheus`) | **Cloud Monitoring / Managed Service for Prometheus** | Automatically scrapes the application's `/metrics` endpoint (or ingests metrics via Cloud Monitoring sidecar). |
| **Dashboards & Alerting** (`Grafana`) | **Cloud Monitoring Dashboards** | Displays real-time request rates, HTTP status code breakdowns, and p95 request duration histograms with metric-based alerting rules. |
| **Rollback Mechanism** (`git revert` / redeploy) | **Cloud Run Traffic Splitting & Revisions** | Instant zero-downtime rollback by updating Cloud Run traffic distribution (`gcloud run services update-traffic --to-revisions=PREVIOUS_REVISION=100`) or reverting git commit. |

