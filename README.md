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

## Cloud mapping

The local stack maps directly to a small AWS deployment without changing the
application contract:

| Local component | AWS equivalent | Deployment responsibility |
|-----------------|----------------|---------------------------|
| Docker image | Amazon ECR | Store the versioned service image |
| Docker Compose app | Amazon ECS on Fargate | Run the app behind an Application Load Balancer |
| `/health` | ECS container health check and ALB target check | Remove unhealthy tasks from traffic |
| Prometheus | Amazon Managed Service for Prometheus | Scrape `/metrics` through a private network path |
| Grafana | Amazon Managed Grafana | Query Prometheus and display the Service Overview dashboard |
| GitHub Actions | OIDC federated deploy role | Build, test, push the image, and update the ECS service |

The container keeps port `3000`, the load balancer publishes the user-facing
port, and `SERVICE_NAME`, `APP_VERSION`, and `MAINTENANCE_MODE` remain runtime
environment variables. Production secrets should be supplied through AWS
Secrets Manager or Systems Manager Parameter Store rather than committed to
Compose or workflow files.

For rollback, deploy the previous immutable ECR image tag or ECS task-definition
revision, then confirm the ALB health check and `/metrics` series recover. The
same procedure is exercised locally with `git revert <commit>` followed by
`docker compose up -d --build`.

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
