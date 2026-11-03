#!/usr/bin/env bash
# Test rollback of the Compose-managed app while Prometheus and Grafana stay up.
# The EXIT trap attempts recovery even when an assertion fails mid-test.
set -Eeuo pipefail

GOOD_IMAGE="${GOOD_IMAGE:-ci-container-monitoring-lab:local}"
CANDIDATE_IMAGE="${CANDIDATE_IMAGE:-ci-container-monitoring-lab:candidate}"
APP_URL="${APP_URL:-http://127.0.0.1:8080}"
PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3000}"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"
CANDIDATE_DEPLOYED=false
ROLLBACK_COMPLETE=false
mkdir -p "$EVIDENCE_DIR"

wait_for_app_healthy() {
  for attempt in $(seq 1 30); do
    container_id="$(docker compose ps -q app 2>/dev/null || true)"
    if [[ -n "$container_id" ]]; then
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>/dev/null || true)"
      if [[ "$health" == "healthy" ]] && curl --silent --fail "$APP_URL/health" >/dev/null; then
        echo "Compose app is healthy (container $container_id)"
        return 0
      fi
    fi
    sleep 3
  done
  docker compose ps -a || true
  docker compose logs --no-color app || true
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

restore_known_good() {
  echo "Restoring known-good image $GOOD_IMAGE on the Compose app service"
  APP_IMAGE="$GOOD_IMAGE" APP_RESTART_POLICY=unless-stopped docker compose up -d --no-build --force-recreate app
  wait_for_app_healthy
}

on_exit() {
  status=$?
  trap - EXIT
  if [[ "$CANDIDATE_DEPLOYED" == "true" && "$ROLLBACK_COMPLETE" != "true" ]]; then
    echo "Test exited before completing rollback; attempting automatic Compose recovery"
    set +e
    restore_known_good
    recovery_status=$?
    if [[ $recovery_status -eq 0 ]]; then
      wait_for_prometheus_up
      recovery_status=$?
    fi
    echo "Automatic recovery exit status: $recovery_status"
  fi
  exit "$status"
}
trap on_exit EXIT

# Confirm the stack is healthy and build the known-good image used for rollback.
wait_for_app_healthy
curl --silent --show-error --fail "$PROM_URL/-/ready" >/dev/null
curl --silent --show-error --fail "$GRAFANA_URL/api/health" > "$EVIDENCE_DIR/grafana-health-before-rollback.json"
docker compose ps -a | tee "$EVIDENCE_DIR/compose-before-rollback.txt"
APP_IMAGE="$GOOD_IMAGE" docker compose build app

# Build a test-only candidate that exits non-zero during startup.
docker build --build-arg "BASE_IMAGE=$GOOD_IMAGE" -f scripts/Dockerfile.rollback-candidate -t "$CANDIDATE_IMAGE" .
echo "Deploying intentionally faulty image into the existing Compose app service"
APP_IMAGE="$CANDIDATE_IMAGE" APP_RESTART_POLICY=no docker compose up -d --no-build --force-recreate app
CANDIDATE_DEPLOYED=true

# Verify that the Compose-managed app container really exited non-zero.
container_id="$(docker compose ps -aq app)"
if [[ -z "$container_id" ]]; then
  echo "Could not find the Compose-managed candidate container"
  exit 1
fi
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
  echo "Candidate did not fail as expected (state=$state exit_code=$exit_code)"
  docker compose logs --no-color app || true
  exit 1
fi
echo "Compose candidate failed as expected (exit code $exit_code)"
docker inspect "$container_id" > "$EVIDENCE_DIR/failed-compose-candidate.json"
docker compose ps -a | tee "$EVIDENCE_DIR/compose-candidate-failed.txt"

# Roll back the SAME Compose app service to the previously verified image.
restore_known_good
wait_for_prometheus_up
curl --silent --show-error --fail "$GRAFANA_URL/api/health" | tee "$EVIDENCE_DIR/grafana-health-after-rollback.json"
curl --silent --show-error --fail "$GRAFANA_URL/api/search?query=Service%20Overview" \
  | jq -e 'any(.[]; .title == "Service Overview")' \
  | tee "$EVIDENCE_DIR/grafana-dashboard-after-rollback.json"
curl --silent --show-error --fail "$GRAFANA_URL/api/datasources/proxy/uid/prometheus/api/v1/query?query=up%7Bjob%3D%22ci-container-monitoring-lab%22%7D" \
  | jq -e '.data.result[0].value[1] == "1"' \
  | tee "$EVIDENCE_DIR/grafana-prometheus-query-after-rollback.json"
curl --silent --show-error --fail "$GRAFANA_URL/api/datasources/proxy/uid/prometheus/api/v1/query?query=http_requests_total" \
  | jq -e '.data.result | length > 0' \
  | tee "$EVIDENCE_DIR/grafana-live-metrics-after-rollback.json"
docker compose ps -a | tee "$EVIDENCE_DIR/compose-after-rollback.txt"

ROLLBACK_COMPLETE=true
echo "Compose rollback passed: candidate failed, known-good app recovered, Prometheus UP, Grafana dashboard and live metrics verified."
