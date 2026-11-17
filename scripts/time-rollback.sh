#!/usr/bin/env bash
# Time a rollback of a deliberately broken deploy, automatic vs manual.
#
# Usage:  GOOD_IMAGE=localhost:5000/demo:<sha> ./scripts/time-rollback.sh auto   [runs]
#         GOOD_IMAGE=localhost:5000/demo:<sha> ./scripts/time-rollback.sh manual [runs]
#
# Each run: (1) deploy the known-good image so there is a stable version,
#           (2) deploy the SAME image with FAIL_HEALTH=true (health checks fail),
#           (3) measure until the good config is serving again.
#
#   auto   = job has auto_revert=true; Nomad reverts by itself.
#   manual = job has auto_revert=false; the script runs `nomad job revert` after
#            HUMAN_REACTION_SECONDS (default 0). Real human reaction time is NOT
#            measured; set HUMAN_REACTION_SECONDS to model it (e.g. 120).
#
# Columns (seconds): detect = submit -> deployment marked failed
#                    human  = failed -> revert command issued (manual only)
#                    revert = revert starts -> good config healthy again
#                    total  = submit -> healthy again
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:?usage: time-rollback.sh auto|manual [runs]}"
RUNS="${2:-3}"
: "${GOOD_IMAGE:?set GOOD_IMAGE, e.g. localhost:5000/demo:<sha>}"
JOB_NAME="${JOB_NAME:-demo}"
EXPECTED_COUNT="${EXPECTED_COUNT:-2}"
HUMAN_REACTION_SECONDS="${HUMAN_REACTION_SECONDS:-0}"
CONSUL_ADDR="${CONSUL_ADDR:-http://127.0.0.1:8500}"
RECOVER_TIMEOUT="${RECOVER_TIMEOUT:-300}"
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

case "$MODE" in
  auto)   AR=true ;;
  manual) AR=false ;;
  *) echo "mode must be auto or manual" >&2; exit 2 ;;
esac

# "Healthy again" = spec has FAIL_HEALTH=false, exactly N desired allocs all running,
# and Consul reports N passing instances.
recovered() {
  local spec_ok allocs_ok passing
  spec_ok=$(nomad job inspect -json "$JOB_NAME" | jq -r '(.Job // .) | [.TaskGroups[].Tasks[].Env.FAIL_HEALTH] | all(. == "false")')
  allocs_ok=$(nomad job allocs -json "$JOB_NAME" | jq --argjson n "$EXPECTED_COUNT" '[.[] | select(.DesiredStatus == "run")] | (length == $n) and all(.ClientStatus == "running")')
  passing=$(curl -fsS "$CONSUL_ADDR/v1/health/service/$JOB_NAME?passing=true" | jq length)
  [[ "$spec_ok" == "true" && "$allocs_ok" == "true" && "$passing" == "$EXPECTED_COUNT" ]]
}

wait_recovered() {  # prints the epoch second at which recovery was observed
  local end=$(( $(date +%s) + RECOVER_TIMEOUT ))
  until recovered 2>/dev/null; do
    if (( $(date +%s) >= end )); then echo "timed out waiting for recovery" >&2; return 1; fi
    sleep 1
  done
  date +%s
}

median() { sort -n | awk '{a[NR]=$1} END{ if(NR%2){print a[(NR+1)/2]} else {print (a[NR/2]+a[NR/2+1])/2} }'; }

mkdir -p results
OUT="results/timing-${MODE}-$(date +%Y%m%d-%H%M%S).csv"
echo "run,mode,detect_s,human_s,revert_s,total_s" | tee "$OUT"

for run in $(seq 1 "$RUNS"); do
  tf=$(mktemp)

  # 1. known-good, stable baseline (auto_revert set for this mode)
  IMAGE="$GOOD_IMAGE" FAIL_HEALTH=false AUTO_REVERT="$AR" ALLOW_NO_DEPLOYMENT=true ./scripts/deploy.sh >&2
  wait_recovered >/dev/null
  good_version=$(nomad job inspect -json "$JOB_NAME" | jq -r '(.Job // .) | .Version')

  # 2. break it on purpose; REVERT_WAIT=0 so deploy.sh returns the moment the deployment fails
  set +e
  TIMING_FILE="$tf" REVERT_WAIT=0 IMAGE="$GOOD_IMAGE" FAIL_HEALTH=true AUTO_REVERT="$AR" ./scripts/deploy.sh >&2
  rc=$?
  set -e
  if [[ $rc -ne 1 ]]; then echo "run $run: expected the bad deploy to FAIL (exit 1), got exit $rc" >&2; exit 1; fi
  t_sub=$(awk '$1=="submitted"{print $2}' "$tf"); t_fail=$(awk '$1=="failed"{print $2}' "$tf")

  # 3. recovery
  if [[ "$MODE" == "manual" ]]; then
    sleep "$HUMAN_REACTION_SECONDS"
    t_cmd=$(date +%s)
    nomad job revert -detach "$JOB_NAME" "$good_version" >/dev/null
  else
    t_cmd=$t_fail   # Nomad is already reverting on its own
  fi
  t_done=$(wait_recovered)

  echo "$run,$MODE,$((t_fail - t_sub)),$((t_cmd - t_fail)),$((t_done - t_cmd)),$((t_done - t_sub))" | tee -a "$OUT"
  rm -f "$tf"
done

echo
echo "MEDIANS over $RUNS run(s) [seconds]"
for col in 3:detect 4:human 5:revert 6:total; do
  idx="${col%%:*}"; name="${col##*:}"
  printf '  %-7s %s\n' "$name" "$(tail -n +2 "$OUT" | cut -d, -f"$idx" | median)"
done
echo "raw data: $OUT"
