#!/usr/bin/env bash
# Capture proof of a rollback straight from Nomad into docs/evidence/<timestamp>/.
# Run it right AFTER a bad deploy has failed and reverted (or after the timing runs).
# Read-only: it only queries Nomad.
set -euo pipefail
cd "$(dirname "$0")/.."
JOB_NAME="${JOB_NAME:-demo}"
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"
OUT="docs/evidence/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

{ date -u +"captured: %Y-%m-%dT%H:%M:%SZ"; nomad version; consul version | head -1; docker --version; } > "$OUT/environment.txt" 2>&1 || true

# Versions: the Stable flag and the new version created by an auto-revert
nomad job history "$JOB_NAME"       > "$OUT/job-history.txt"  2>&1 || true
nomad job deployments "$JOB_NAME"   > "$OUT/deployments.txt"  2>&1 || true
nomad job status "$JOB_NAME"        > "$OUT/job-status.txt"   2>&1 || true
nomad job allocs "$JOB_NAME"        > "$OUT/allocs.txt"       2>&1 || true

# Per-deployment detail: status and the failure reason
for id in $(nomad job deployments -json "$JOB_NAME" 2>/dev/null | jq -r '.[].ID' 2>/dev/null || true); do
  nomad deployment status -json "$id" 2>/dev/null \
    | jq '{ID, JobVersion, Status, StatusDescription, TaskGroups}' > "$OUT/deployment-${id%%-*}.json" 2>/dev/null || true
done

# Allocation events (canary killed, health check failures)
for a in $(nomad job allocs -json "$JOB_NAME" 2>/dev/null | jq -r '.[].ID' 2>/dev/null || true); do
  nomad alloc status "$a" > "$OUT/alloc-${a%%-*}.txt" 2>&1 || true
done

echo "Evidence saved to $OUT"
ls -1 "$OUT"
echo
echo "Commit it and link it from the PR:  git add docs/evidence && git commit -m 'Add rollback evidence'"
