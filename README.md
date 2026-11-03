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
docker compose up -d --build
docker compose ps
docker compose logs -f app
```

Services once up:

| Service | URL |
|---|---|
| App | http://localhost:8080 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 |

Grafana logs in anonymously (admin/admin also works). Open the **Service
Overview** dashboard under the **Lab** folder.

Tear down:

```bash
docker compose down
```

## Verify the service and monitoring

```bash
curl -fsS http://localhost:8080/health
curl -fsS http://localhost:8080/
curl -fsS http://localhost:8080/metrics
```

Check the Prometheus scrape target at
`http://localhost:9090/targets`. The `ci-container-monitoring-lab` target
should be **UP**. Generate requests, then open Grafana at `http://localhost:3000`
and inspect **Lab → Service Overview**. The request-rate and p95-duration
panels should show time-series data. The CI artifact records API-level checks;
capture a browser screenshot of the visible panels from your local deployment
for reviewer-facing visual evidence.

Generate sample traffic:

```bash
./scripts/generate-traffic.sh
# Optional: provide the URL and request count
./scripts/generate-traffic.sh http://localhost:8080 500
```

## Run the tests locally

```bash
cd app
npm install
npm test
cd ..
docker compose config
```

## GitHub Actions

The workflow runs on pushes and pull requests. It installs locked dependencies
on Node.js 20, runs the service tests, starts the complete Docker Compose stack,
waits for the app, Prometheus and Grafana, generates request traffic, verifies
that Prometheus reports the app target as UP and has request metrics, and checks
that Grafana has loaded the Service Overview dashboard and can query live
Prometheus metrics through its provisioned datasource. It then replaces the
app image inside the running Compose deployment with a deliberately failing
candidate, confirms the Compose app container exits non-zero, restores the
known-good image through Compose, and verifies app health, Prometheus target
recovery, and Grafana datasource/dashboard access. CI uploads the health,
target, dashboard, failed-candidate, and post-rollback Compose evidence as a
workflow artifact.

## Rollback readiness

Keep releases in version control and use a revert commit to back out a bad
change without rewriting shared history:

```bash
git log --oneline
git revert <bad-commit-sha>
docker compose up -d --build
docker compose ps
curl -fsS http://localhost:8080/health
```

For a repeatable recovery check, start the complete Compose stack and run:

```bash
docker compose up -d --build
./scripts/generate-traffic.sh http://localhost:8080 200
./scripts/rollback-smoke-test.sh
docker compose ps
```

The rollback test changes the image of the existing Compose `app` service to a
test-only candidate image that intentionally exits during startup. It verifies
the Compose-managed app container exits non-zero, restores the known-good
image on that same Compose service, and waits for the app health check and
Prometheus target to recover. It also verifies the Grafana dashboard and a live
metric query through Grafana's Prometheus datasource proxy. Prometheus and
Grafana remain part of the same Compose deployment throughout the rollback.

## Cloud release mapping (documentation only)

The local pipeline maps to a cloud release as follows. This lab does not deploy
to the cloud and these steps do not need to be run for the assignment.

| Local step | Cloud equivalent | Purpose |
|---|---|---|
| Git commit and pull request | GitHub repository and protected-branch review | Review changes before release |
| GitHub Actions tests and Docker build | Cloud Build or GitHub Actions with cloud authentication | Test and build a repeatable image |
| Local Docker image | Push the image to Artifact Registry | Store a versioned container image |
| Docker Compose app service | Deploy the image to Cloud Run | Run the container as a managed service |
| Prometheus metrics and Grafana dashboard | Cloud Monitoring metrics, dashboards, and alerting | Observe service health, latency, traffic, and errors |
| Git revert / previous image | Roll back to a previous Cloud Run revision | Restore the last known-good release |

A typical cloud release would build and tag the image with the commit SHA, push
it to **Artifact Registry**, deploy that exact image to **Cloud Run**, and use
**Cloud Monitoring** to inspect request count, latency, error rates, and service
health. Keep credentials in the CI secret store or workload identity mechanism;
never commit service-account keys or other secrets. For rollback, route traffic
back to a previous healthy Cloud Run revision. No cloud resources are created
and no billing is incurred by completing this documentation step.
