#!/usr/bin/env bash
# READ-ONLY audit of the update settings of every service job on a Nomad cluster.
# Prints one row per task group and flags the risky ones (e.g. auto_revert off).
#
# Usage: NOMAD_ADDR=http://127.0.0.1:4646 ./scripts/audit-update-blocks.sh
set -euo pipefail
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"
FILTER="$(dirname "$0")/audit-update-blocks.jq"

{
  printf 'JOB\tGROUP\tCOUNT\tCANARY\tAUTO_REVERT\tAUTO_PROMOTE\tHEALTH_CHECK\tMIN_HEALTHY_S\tHEALTHY_DEADLINE_S\tPROGRESS_DEADLINE_S\tFLAGS\n'
  for job in $(nomad job status -json | jq -r '.[] | select(.Type == "service") | .ID'); do
    nomad job inspect -json "$job" | jq -r -f "$FILTER"
  done
} | if command -v column >/dev/null; then column -t -s "$(printf '\t')"; else cat; fi
