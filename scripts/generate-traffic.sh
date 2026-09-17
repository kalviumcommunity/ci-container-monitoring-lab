#!/usr/bin/env bash
# Generate sample traffic so the metrics and dashboards have data to show.
# Usage: ./scripts/generate-traffic.sh [base_url] [requests]
set -euo pipefail

BASE_URL="${1:-http://localhost:8081}"
COUNT="${2:-200}"
ROUTES=("/" "/health" "/work" "/metrics")

echo "Sending ${COUNT} requests to ${BASE_URL} ..."
for i in $(seq 1 "${COUNT}"); do
  route="${ROUTES[$((RANDOM % ${#ROUTES[@]}))]}"
  curl -s -o /dev/null "${BASE_URL}${route}" || true
  sleep 0.1
done
echo "Done."
