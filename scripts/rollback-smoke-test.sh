#!/usr/bin/env bash
# Exercise rollback of the actual Compose app service, keeping Prometheus and
# Grafana running throughout the failed deployment and recovery.
set -euo pipefail

GOOD_IMAGE="${GOOD_IMAGE:-ci-container-monitoring-lab:local}"
CANDIDATE_IMAGE="${CANDIDATE_IMAGE:-ci-container-monitoring-lab:candidate}"
APP_URL="${APP_URL:-http://127.0.0.1:8080}"
PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3000}"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"
mkdir -p "$EVIDENCE_DIR"

wait_for_app_healthy() {
  for attempt in $(seq 1 30); do
    container_id="$(docker compose ps -q app)"
    if [[ -n "$container_id" ]]; then
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
      if [[ "$health" == "healthy" ]] && curl --silent --fail "$APP_URL/health" >/dev/null; then
        echo "Compose app is healthy (container $container_id)"
        return 0
      fi
    fi
    sleep 3
  done
  docker compose ps
  docker compose logs --no-color app
  return 1
}

wait_for_prometheus_up() {
  for attempt in $(seq 1 30); do
    result="$(curl --silent --fail "$PROM_URL/api/v1/query?query=up%7Bjob%3D%22ci-container-monitoring-lab%22%7D" || true)"
    if echo "$result" | jq -e '.data.result[0].value[1] == "1"' >/dev/null 2>&1; then
      echo "Prometheus reports the Compose app target UP"
      return 0
    fi
    sleep 3
  done
  echo "Prometheus target did not return to UP"
  return 1
}

# Capture the known-good Compose stack before introducing a failed release.
wait_for_app_healthy
docker compose ps | tee "$EVIDENCE_DIR/compose-before-rollback.txt"
docker compose build app

# Build a candidate from the known-good image that intentionally exits at startup.
docker build -f scripts/Dockerfile.rollback-candidate -t "$CANDIDATE_IMAGE" .
echo "Deploying deliberately faulty image into the existing Compose app service"
APP_IMAGE="$CANDIDATE_IMAGE" APP_RESTART_POLICY=no docker compose up -d --no-build --force-recreate app

# The Compose-managed app container must exit non-zero; this is the failed deployment.
container_id="$(docker compose ps -aq app)"
failed=false
for attempt in $(seq 1 30); do
  state="$(docker inspect --format '{{.State.Status}}' "$container_id")"
  exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container_id")"
  if [[ "$state" == "exited" && "$exit_code" != "0" ]]; then
    failed=true
    break
  fi
  sleep 2
done
if [[ "$failed" != "true" ]]; then
  echo "Compose candidate did not fail as expected (state=$state exit_code=$exit_code)"
  docker compose logs --no-color app || true
  exit 1
fi
echo "Compose candidate failed as expected (exit code $exit_code)"
docker inspect "$container_id" > "$EVIDENCE_DIR/failed-compose-candidate.json"
docker compose ps -a | tee "$EVIDENCE_DIR/compose-candidate-failed.txt"

# Restore the known-good image on the same Compose service, not a separate container.
echo "Rolling back Compose app service to $GOOD_IMAGE"
APP_IMAGE="$GOOD_IMAGE" APP_RESTART_POLICY=unless-stopped docker compose up -d --no-build --force-recreate app
wait_for_app_healthy
wait_for_prometheus_up

# Verify monitoring survived/recovered and Grafana still serves the provisioned dashboard.
curl --silent --show-error --fail "$GRAFANA_URL/api/health" | tee "$EVIDENCE_DIR/grafana-health-after-rollback.json"
curl --silent --show-error --fail "$GRAFANA_URL/api/search?query=Service%20Overview" \
  | jq -e 'any(.[]; .title == "Service Overview")' \
  | tee "$EVIDENCE_DIR/grafana-dashboard-after-rollback.json"
curl --silent --show-error --fail "$GRAFANA_URL/api/datasources/proxy/uid/prometheus/api/v1/query?query=up%7Bjob%3D%22ci-container-monitoring-lab%22%7D" \
  | jq -e '.data.result[0].value[1] == "1"' \
  | tee "$EVIDENCE_DIR/grafana-prometheus-query-after-rollback.json"

docker compose ps | tee "$EVIDENCE_DIR/compose-after-rollback.txt"
echo "Compose rollback passed: failed app image replaced, app healthy, Prometheus target UP, Grafana dashboard/data source reachable."
