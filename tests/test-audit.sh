#!/usr/bin/env bash
# Checks the audit filter flags risky update blocks. Needs jq.
set -uo pipefail
cd "$(dirname "$0")/.."
rows=$(jq -c '.[]' tests/audit-sample.json | while read -r j; do echo "$j" | jq -r -f scripts/audit-update-blocks.jq; done)
fail=0
check() { if echo "$rows" | grep -P "$1" >/dev/null; then echo "PASS  $2"; else echo "FAIL  $2"; fail=1; fi; }
check '^good-svc\t.*\tok$'                          "healthy config is not flagged"
check '^risky-svc\t.*NO_AUTO_REVERT'                "auto_revert off is flagged"
check '^risky-svc\t.*NO_CANARY'                     "canary = 0 is flagged"
check '^risky-svc\t.*SINGLE_INSTANCE'               "count = 1 is flagged"
check '^risky-svc\t.*HEALTH_CHECK=task_states'      "health_check other than checks is flagged"
check '^risky-svc\t.*NO_PROGRESS_DEADLINE'          "progress_deadline = 0 is flagged"
check '^job-level\t.*\tok$'                         "job-level update block is picked up"
check '^no-update\t.*NO_UPDATE_BLOCK'               "missing update block is flagged"
if echo "$rows" | grep -q '^batch-job'; then echo "FAIL  batch jobs are skipped"; fail=1; else echo "PASS  batch jobs are skipped"; fi
exit $fail
