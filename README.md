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

## Cloud Mapping

The local workflow (**commit → CI → container → deploy → dashboard**) maps directly to managed Google Cloud services for production deployments:

| Stage | Local Implementation | Equivalent Cloud Service / Pattern |
|-------|----------------------|-----------------------------------|
| **CI / Build** | GitHub Actions (test & local docker build) | GitHub Actions / Cloud Build running unit tests and building container images |
| **Artifact Storage** | Local Docker daemon image cache | **Google Artifact Registry** (`us-central1-docker.pkg.dev/<PROJECT_ID>/<REPO>/<IMAGE>:<TAG>`) |
| **Runtime / Deployment** | Docker Compose (`lab-app` container) | **Google Cloud Run** (managed serverless container deployment) |
| **Service Health** | Docker Compose `healthcheck` (`/health`) | Cloud Run Startup & Liveness Probes against `/health` |
| **Metrics Collection** | Prometheus scraping `/metrics` (port 3000) | **Google Cloud Managed Service for Prometheus (GMP)** scraping `/metrics` + Cloud Monitoring Native Metrics |
| **Dashboards / Observability** | Grafana ("Service Overview" dashboard) | **Cloud Monitoring Dashboards** (metrics explorer, SLO monitoring, alerting) |
| **Rollback** | Git revert + `docker compose up -d --build` | **Cloud Run Revision Traffic Splitting / Rollback** (`gcloud run services update-traffic --to-revisions`) or CI automated revert |

### Cloud Workflow Summary

1. **Build & Push to Artifact Registry:**
   ```bash
   # Build image and tag with commit SHA
   docker build -t us-central1-docker.pkg.dev/$PROJECT_ID/lab-repo/app:$GITHUB_SHA .
   # Push to Google Artifact Registry
   docker push us-central1-docker.pkg.dev/$PROJECT_ID/lab-repo/app:$GITHUB_SHA
   ```

2. **Deploy to Cloud Run:**
   ```bash
   gcloud run deploy lab-app \
     --image us-central1-docker.pkg.dev/$PROJECT_ID/lab-repo/app:$GITHUB_SHA \
     --region us-central1 \
     --port 3000 \
     --set-env-vars SERVICE_NAME=ci-container-monitoring-lab,APP_VERSION=1.0.0 \
     --allow-unauthenticated
   ```

3. **Monitor with Cloud Monitoring:**
   - Use Cloud Run's built-in metrics for request counts, latency histograms, and container utilization.
   - Use Google Cloud Managed Service for Prometheus to scrape custom application metrics (`/metrics`) and visualize them in Cloud Monitoring custom dashboards.

4. **Zero-Downtime Rollback:**
   ```bash
   # Instantly route 100% of traffic back to the previous healthy revision
   gcloud run services update-traffic lab-app --to-revisions=PREVIOUS_REVISION_NAME=100
   ```
