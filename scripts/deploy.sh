#!/usr/bin/env bash
# Deploy the demo job to Nomad and WAIT for the rollout to finish.
#
# Required env: IMAGE   e.g. localhost:5000/demo:<git-sha>
# Optional env: FAIL_HEALTH CRASH_ON_START STARTUP_DELAY_MS AUTO_REVERT
#               JOB_FILE JOB_NAME NOMAD_ADDR POLL_INTERVAL DEPLOY_TIMEOUT
#               DEPLOYMENT_APPEAR_TIMEOUT REVERT_WAIT ALLOW_NO_DEPLOYMENT TIMING_FILE
#
# Exit codes:
#   0  rollout finished successfully (or nothing changed)
#   1  rollout FAILED or was cancelled (auto-revert may have already put the old version back)
#   2  timeout, no deployment to watch, or usage/tooling error
set -euo pipefail

JOB_FILE="${JOB_FILE:-nomad/demo.nomad.hcl}"
JOB_NAME="${JOB_NAME:-demo}"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}"
DEPLOYMENT_APPEAR_TIMEOUT="${DEPLOYMENT_APPEAR_TIMEOUT:-30}"
REVERT_WAIT="${REVERT_WAIT:-60}"
POLL_INTERVAL="${POLL_INTERVAL:-3}"
ALLOW_NO_DEPLOYMENT="${ALLOW_NO_DEPLOYMENT:-false}"
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

: "${IMAGE:?set IMAGE, e.g. IMAGE=localhost:5000/demo:abc123}"
command -v nomad >/dev/null || { echo "nomad CLI not found" >&2; exit 2; }
command -v jq    >/dev/null || { echo "jq not found" >&2; exit 2; }

log()     { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
summary() { if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then echo "$*" >> "$GITHUB_STEP_SUMMARY"; fi; return 0; }
stamp()   { if [[ -n "${TIMING_FILE:-}" ]]; then echo "$1 $(date +%s)" >> "$TIMING_FILE"; fi; return 0; }

VARS=(
  -var "image=${IMAGE}"
  -var "fail_health=${FAIL_HEALTH:-false}"
  -var "crash_on_start=${CRASH_ON_START:-false}"
  -var "startup_delay_ms=${STARTUP_DELAY_MS:-0}"
  -var "auto_revert=${AUTO_REVERT:-true}"
)

job_version() {
  nomad job inspect -json "$JOB_NAME" 2>/dev/null | jq -r '(.Job // .) | .Version' 2>/dev/null || echo -1
}

running_image() {
  nomad job inspect -json "$JOB_NAME" 2>/dev/null \
    | jq -r '(.Job // .) | [.TaskGroups[].Tasks[].Config.image] | unique | join(",")' 2>/dev/null || echo unknown
}

find_deployment() {  # $1 = job version
  nomad job deployments -json "$JOB_NAME" 2>/dev/null \
    | jq -r --argjson v "$1" '[.[] | select(.JobVersion == $v)] | sort_by(.CreateIndex) | last | .ID // empty' 2>/dev/null || true
}

deployment_status() {  # $1 = deployment id
  nomad deployment status -json "$1" 2>/dev/null | jq -r '.Status' 2>/dev/null || echo unknown
}

diagnose() {
  log "---- diagnostics ----"
  nomad job status "$JOB_NAME" || true
  nomad deployment status "$dep" || true
  local a
  for a in $(nomad job allocs -json "$JOB_NAME" 2>/dev/null | jq -r '.[] | select(.DeploymentStatus.Healthy == false) | .ID' 2>/dev/null || true); do
    log "unhealthy allocation $a"
    nomad alloc status "$a" 2>&1 | sed -n '1,40p' || true
  done
  log "---------------------"
}

wait_for_revert() {
  if [[ "$REVERT_WAIT" -le 0 ]]; then return 0; fi
  local end=$(( $(date +%s) + REVERT_WAIT )) rdep="" st=""
  while (( $(date +%s) < end )); do
    rdep=$(nomad job deployments -json "$JOB_NAME" 2>/dev/null \
      | jq -r --argjson v "$new" '[.[] | select(.JobVersion > $v)] | sort_by(.JobVersion) | last | .ID // empty' 2>/dev/null || true)
    if [[ -n "$rdep" ]]; then
      st=$(deployment_status "$rdep")
      case "$st" in
        successful)       log "auto-revert deployment $rdep: successful"; return 0 ;;
        failed|cancelled) log "auto-revert deployment $rdep: $st"; return 1 ;;
      esac
    fi
    sleep "$POLL_INTERVAL"
  done
  log "no auto-revert deployment finished within ${REVERT_WAIT}s (auto_revert off, nothing stable to revert to, or the revert needed no deployment)"
  return 0
}

# ---- submit -------------------------------------------------------------
log "validating $JOB_FILE"
nomad job validate "${VARS[@]}" "$JOB_FILE" >/dev/null

prev=$(job_version)
log "image=$IMAGE  previous job version=$prev"

stamp submitted
nomad job run -detach "${VARS[@]}" "$JOB_FILE" >/dev/null
new=$(job_version)

if [[ "$new" == "$prev" ]]; then
  log "job spec unchanged (still version $new); nothing to deploy"
  exit 0
fi
log "registered job version $new"

# ---- find the deployment for this version -------------------------------
dep=""
appear_end=$(( $(date +%s) + DEPLOYMENT_APPEAR_TIMEOUT ))
while [[ -z "$dep" ]]; do
  dep=$(find_deployment "$new")
  if [[ -n "$dep" ]]; then break; fi
  if (( $(date +%s) >= appear_end )); then
    if [[ "$ALLOW_NO_DEPLOYMENT" == "true" ]]; then
      log "WARNING: no deployment created for version $new (non-destructive change); continuing"
      exit 0
    fi
    log "ERROR: Nomad created no deployment for version $new, so the rollout cannot be verified"
    log "       (no update block? change that does not replace allocations?)"
    exit 2
  fi
  sleep "$POLL_INTERVAL"
done
log "watching deployment $dep"

# ---- wait for the rollout to finish -------------------------------------
end=$(( $(date +%s) + DEPLOY_TIMEOUT ))
last=""
failed=0
while true; do
  status=$(deployment_status "$dep")
  if [[ "$status" != "$last" ]]; then log "deployment $dep: $status"; last="$status"; fi
  case "$status" in
    successful) break ;;
    failed|cancelled) failed=1; break ;;
  esac
  if (( $(date +%s) >= end )); then
    log "ERROR: timed out after ${DEPLOY_TIMEOUT}s waiting for deployment $dep (last status: $status)"
    diagnose
    exit 2
  fi
  sleep "$POLL_INTERVAL"
done

# ---- result -------------------------------------------------------------
if [[ "$failed" -eq 1 ]]; then
  stamp failed
  desc=$(nomad deployment status -json "$dep" 2>/dev/null | jq -r '.StatusDescription' 2>/dev/null || echo "")
  log "ROLLOUT FAILED: $desc"
  diagnose
  wait_for_revert || true
  log "image now configured: $(running_image)"
  summary "### Deploy FAILED for \`$IMAGE\`"
  summary "Deployment \`$dep\`: $desc. Currently configured image: \`$(running_image)\`."
  exit 1
fi

log "ROLLOUT SUCCESSFUL: now running $(running_image)"
nomad job status "$JOB_NAME" || true
summary "### Deploy succeeded: \`$(running_image)\` (job version $new)"
exit 0
