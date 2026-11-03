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
should be **UP**. Grafana's provisioned **Service Overview** dashboard should
show request-rate and request-duration data after requests have been generated.

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
that Grafana has loaded the Service Overview dashboard. It also runs the
rollback smoke test below. CI saves a machine-readable integration report as a
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

For a repeatable automated recovery check, run the rollback smoke test after
building the app image:

```bash
docker compose build app
./scripts/rollback-smoke-test.sh ci-container-monitoring-lab:local
```

The test first verifies the known-good image, builds a separate test-only
candidate image that intentionally exits during startup, confirms that the
candidate container terminates with a non-zero exit code, removes it, and
re-deploys the previously verified known-good image. It then requires HTTP 200
from the recovered service. This exercises an actual image replacement and
recovery path; it does not claim that a production release was rolled back.

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
