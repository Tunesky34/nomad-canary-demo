#!/usr/bin/env bash
# Build the image and prove /health works, with and without FAIL_HEALTH.
set -euo pipefail
cd "$(dirname "$0")/.."

IMG=demo:local
docker build -t "$IMG" app

cleanup() { docker rm -f demo-ok demo-bad >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name demo-ok -p 18080:8080 "$IMG" >/dev/null
docker run -d --name demo-bad -p 18081:8080 -e FAIL_HEALTH=true "$IMG" >/dev/null
sleep 2

ok=$(curl -s -o /dev/null -w '%{http_code}' localhost:18080/health)
bad=$(curl -s -o /dev/null -w '%{http_code}' localhost:18081/health)
echo "healthy build  -> $ok (expect 200)"
echo "FAIL_HEALTH    -> $bad (expect 500)"
[[ "$ok" == 200 && "$bad" == 500 ]] && echo "PASS" || { echo "FAIL"; exit 1; }
