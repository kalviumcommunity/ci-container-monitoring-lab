#!/usr/bin/env bash
# Verify image rollback: a known-good release is replaced by a candidate image
# that exits at startup, then the known-good image is restored.
set -euo pipefail

GOOD_IMAGE="${1:-ci-container-monitoring-lab:local}"
CANDIDATE_IMAGE="${2:-ci-container-monitoring-lab:candidate}"
PORT="${ROLLBACK_TEST_PORT:-18080}"
BASE_URL="http://127.0.0.1:${PORT}"
GOOD_CONTAINER="rollback-known-good"
CANDIDATE_CONTAINER="rollback-candidate"

cleanup() {
  docker rm -f "$GOOD_CONTAINER" "$CANDIDATE_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_health() {
  for attempt in $(seq 1 20); do
    if curl --silent --fail "$BASE_URL/health" >/dev/null; then
      echo "Known-good release is healthy (HTTP 200)"
      return 0
    fi
    sleep 2
  done
  echo "Known-good release did not become healthy"
  docker logs "$GOOD_CONTAINER" 2>/dev/null || true
  return 1
}

# Verify the currently deployable image before testing the failed candidate.
docker run -d --name "$GOOD_CONTAINER" -p "${PORT}:3000" \
  -e MAINTENANCE_MODE=off "$GOOD_IMAGE" >/dev/null
wait_for_health
docker rm -f "$GOOD_CONTAINER" >/dev/null

# Build a deliberately broken candidate image that exits during startup.
docker build -f scripts/Dockerfile.rollback-candidate -t "$CANDIDATE_IMAGE" .
docker run -d --name "$CANDIDATE_CONTAINER" -p "${PORT}:3000" "$CANDIDATE_IMAGE" >/dev/null

# A failed release must terminate; do not mistake a running but unready app for success.
for attempt in $(seq 1 20); do
  state="$(docker inspect --format '{{.State.Status}}' "$CANDIDATE_CONTAINER")"
  if [[ "$state" == "exited" ]]; then
    break
  fi
  sleep 1
done
if [[ "$state" != "exited" ]]; then
  echo "Faulty candidate unexpectedly remained running (state: $state)"
  docker logs "$CANDIDATE_CONTAINER" || true
  exit 1
fi
exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$CANDIDATE_CONTAINER")"
if [[ "$exit_code" == "0" ]]; then
  echo "Faulty candidate exited successfully; expected a non-zero exit code"
  exit 1
fi
echo "Faulty candidate failed as expected (container exit code $exit_code)"
docker logs "$CANDIDATE_CONTAINER" || true
docker rm -f "$CANDIDATE_CONTAINER" >/dev/null

# Roll back by deploying the previously verified known-good image again.
docker run -d --name "$GOOD_CONTAINER" -p "${PORT}:3000" \
  -e MAINTENANCE_MODE=off "$GOOD_IMAGE" >/dev/null
wait_for_health

echo "Rollback smoke test passed: failed candidate image replaced by the known-good image."
