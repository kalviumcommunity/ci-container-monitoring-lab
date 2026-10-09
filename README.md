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

This section maps our local **commit → CI → container → deploy → dashboard** pipeline to an equivalent production release pipeline on **Google Cloud Platform (GCP)** using **Artifact Registry**, **Cloud Run**, and **Cloud Monitoring**.

### Architectural Mapping Table

| Pipeline Stage | Local Implementation | Cloud Equivalent (Google Cloud Platform) |
|---|---|---|
| **Source Control & CI** | GitHub Actions (`.github/workflows/ci.yml`) | GitHub Actions / GCP Cloud Build |
| **Artifact Storage** | Local Docker Daemon (`ci-container-monitoring-lab:local`) | GCP Artifact Registry (`us-central1-docker.pkg.dev/$PROJECT_ID/app-repo/service:$COMMIT_SHA`) |
| **Container Execution** | Docker Compose (`docker-compose.yml`) | GCP Cloud Run (Serverless container runtime) |
| **Health Probes** | Compose `healthcheck` (`http://localhost:3000/health`) | Cloud Run Startup & Liveness HTTP Probes (`/health`) |
| **Metrics Scrape** | Local Prometheus (`prometheus.yml` target `app:3000/metrics`) | Google Cloud Managed Service for Prometheus / OpenTelemetry Collector |
| **Observability** | Local Grafana (`http://localhost:3000`) | GCP Cloud Monitoring Dashboards & Cloud Logging |

### Cloud Pipeline Execution Flow

1. **Continuous Integration & Build**:
   - On git commit/push, GitHub Actions triggers unit testing (`npm ci && npm test`).
   - GitHub Actions builds the Docker image and authenticates to GCP Artifact Registry using Workload Identity Federation.
   - The built image is tagged with the git commit SHA and pushed:
     ```bash
     gcloud auth configure-docker us-central1-docker.pkg.dev
     docker build -t us-central1-docker.pkg.dev/$PROJECT_ID/app-repo/ci-container-monitoring-lab:$COMMIT_SHA .
     docker push us-central1-docker.pkg.dev/$PROJECT_ID/app-repo/ci-container-monitoring-lab:$COMMIT_SHA
     ```

2. **Continuous Deployment to Cloud Run**:
   - GitHub Actions deploys the container image from Artifact Registry to GCP Cloud Run:
     ```bash
     gcloud run deploy ci-container-monitoring-lab \
       --image=us-central1-docker.pkg.dev/$PROJECT_ID/app-repo/ci-container-monitoring-lab:$COMMIT_SHA \
       --region=us-central1 \
       --platform=managed \
       --port=3000 \
       --set-env-vars="SERVICE_NAME=ci-container-monitoring-lab,APP_VERSION=1.0.0,MAINTENANCE_MODE=off" \
       --health-check-path=/health \
       --allow-unauthenticated
     ```
   - Cloud Run executes HTTP liveness and readiness probes against `/health`. Traffic is routed to the new revision only once probes return `200 OK`.

3. **Metrics Collection & Monitoring**:
   - Cloud Run natively streams system metrics (request rate, execution duration, CPU/memory, 4xx/5xx error rates) directly into GCP Cloud Monitoring.
   - For custom application metrics (`http_requests_total` and `http_request_duration_seconds`), GCP Managed Service for Prometheus automatically scrapes the `/metrics` endpoint on the Cloud Run service revision.
   - Custom Grafana or Cloud Monitoring dashboards display request rate by route and p95 request duration panels.

4. **Cloud Rollback Strategy**:
   - **Instant Traffic Reversion (Zero-Downtime)**: If a faulty release (e.g. `MAINTENANCE_MODE=on` or broken payment subsystem) is deployed to Cloud Run, revert traffic instantly to the last healthy revision without rebuilding:
     ```bash
     # List active revisions
     gcloud run revisions list --service=ci-container-monitoring-lab --region=us-central1

     # Rollback 100% of traffic to the previous healthy revision
     gcloud run services update-traffic ci-container-monitoring-lab \
       --to-revisions=ci-container-monitoring-lab-00001-abc=100 \
       --region=us-central1
     ```
   - **Git-driven Rollback**: Revert the bad commit (`git revert <commit-hash>`) and push to main, triggering CI/CD to build and deploy a fresh healthy revision.

