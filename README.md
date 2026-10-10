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

## Cloud release mapping

This lab runs locally and does not require a cloud deployment, but the same
commit-to-monitored-service flow maps directly to a managed cloud release:

| Local stage | Cloud equivalent |
|-------------|------------------|
| GitHub Actions installs dependencies, runs tests and builds the Docker image | GitHub Actions keeps the same CI gate and builds the release image |
| Local Docker image `ci-container-monitoring-lab:local` | The CI job would tag and push the image to Google Artifact Registry |
| Docker Compose runs the service container and its local dependencies | Cloud Run would deploy the Artifact Registry image as the managed service |
| `/health` and `/metrics` prove the running container is healthy and observable | Cloud Run health checks and Cloud Monitoring metrics/logs provide the managed runtime view |
| Prometheus and Grafana show request rate and latency locally | Cloud Monitoring dashboards and alerts show the same production signals |
| `git revert` plus `docker compose up -d --build` restores the last good local release | A rollback would redeploy the previous Cloud Run revision or a previous image tag |

No cloud resources are required for this assignment. The mapping documents where
each local proof would land in a production-style Google Cloud release: Artifact
Registry for images, Cloud Run for deployment, and Cloud Monitoring for
observability.
