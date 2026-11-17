#!/usr/bin/env bash
# Tests scripts/deploy.sh against a fake nomad CLI. No cluster needed. Needs jq.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/tests/fake-nomad:$PATH"
# Never write test output into a real GitHub job summary or timing file.
unset GITHUB_STEP_SUMMARY TIMING_FILE
export POLL_INTERVAL=0 REVERT_WAIT=5 DEPLOYMENT_APPEAR_TIMEOUT=5 DEPLOY_TIMEOUT=20
pass=0; fail=0

run_case() {  # name scenario want_rc want_text
  local name="$1" scen="$2" want_rc="$3" want_text="$4" out rc
  export FAKE_DIR; FAKE_DIR=$(mktemp -d)
  out=$(FAKE_SCENARIO="$scen" IMAGE=img-new ./scripts/deploy.sh 2>&1); rc=$?
  if [[ $rc -eq $want_rc && "$out" == *"$want_text"* ]]; then
    echo "PASS  $name (rc=$rc)"; pass=$((pass + 1))
  else
    echo "FAIL  $name (rc=$rc, wanted rc=$want_rc and text '$want_text')"; echo "$out" | sed 's/^/      /'; fail=$((fail + 1))
  fi
}

run_case "successful rollout exits 0"               success  0 "ROLLOUT SUCCESSFUL: now running img-new"
run_case "failed rollout exits 1 (CI goes red)"     fail     1 "ROLLOUT FAILED"
run_case "failed rollout reports the auto-revert"   fail     1 "auto-revert deployment dep-revert: successful"
run_case "after revert the old image is configured" fail     1 "image now configured: good-image"
run_case "unreachable nomad exits 2 with a clear message" down 2 "cannot reach Nomad"
run_case "unchanged spec exits 0 with no deploy"    nochange 0 "nothing to deploy"

# The summary writer itself: goes to a temp file, never the real one.
export FAKE_DIR; FAKE_DIR=$(mktemp -d); sumfile=$(mktemp)
FAKE_SCENARIO=fail IMAGE=img-new GITHUB_STEP_SUMMARY="$sumfile" ./scripts/deploy.sh >/dev/null 2>&1
if grep -q "Deploy FAILED for" "$sumfile"; then echo "PASS  job summary is written when GITHUB_STEP_SUMMARY is set"; pass=$((pass + 1))
else echo "FAIL  job summary not written"; fail=$((fail + 1)); fi

echo; echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
