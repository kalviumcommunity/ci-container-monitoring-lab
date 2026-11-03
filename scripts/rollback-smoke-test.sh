#!/usr/bin/env bash
# Exercise rollback by replacing an unhealthy candidate with the known-good image.
# The candidate is deliberately started with the app's fail-closed maintenance
# setting. The recovery step restores the known-good image/configuration.
set -euo pipefail

IMAGE="${1:-ci-container-monitoring-lab:local}"
PORT="${ROLLBACK_TEST_PORT:-18080}"
BASE_URL="http://127.0.0.1:${PORT}"
GOOD_CONTAINER="rollback-known-good"
CANDIDATE_CONTAINER="rollback-candidate"

cleanup() {
  docker rm -f "$GOOD_CONTAINER" "$CANDIDATE_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_status() {
  expected="$1"
  label="$2"
  for attempt in $(seq 1 20); do
    actual="$(curl --silent --output /dev/null --write-out '%{http_code}' "$BASE_URL/health" || true)"
    if [[ "$actual" == "$expected" ]]; then
      echo "$label returned HTTP $actual as expected"
      return 0
    fi
    sleep 2
  done
  echo "$label did not return HTTP $expected (last status: ${actual:-no response})"
  docker logs "$GOOD_CONTAINER" "$CANDIDATE_CONTAINER" 2>/dev/null || true
  return 1
}

# Establish the known-good release and verify it before simulating a bad release.
docker run -d --name "$GOOD_CONTAINER" -p "${PORT}:3000" \
  -e MAINTENANCE_MODE=off "$IMAGE" >/dev/null
wait_for_status 200 "Known-good release"
docker rm -f "$GOOD_CONTAINER" >/dev/null

# Simulate a faulty candidate release whose readiness check fails.
docker run -d --name "$CANDIDATE_CONTAINER" -p "${PORT}:3000" \
  -e MAINTENANCE_MODE=on "$IMAGE" >/dev/null
wait_for_status 503 "Faulty candidate"
docker rm -f "$CANDIDATE_CONTAINER" >/dev/null

# Roll back by restoring the known-good release on the same service port.
docker run -d --name "$GOOD_CONTAINER" -p "${PORT}:3000" \
  -e MAINTENANCE_MODE=off "$IMAGE" >/dev/null
wait_for_status 200 "Rolled-back release"

echo "Rollback smoke test passed: unhealthy candidate replaced by healthy known-good release."
