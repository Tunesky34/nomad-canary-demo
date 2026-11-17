#!/usr/bin/env bash
# Fill docs/results.md from the NEWEST results/timing-auto-*.csv and timing-manual-*.csv.
# Writes measured medians only; nothing is estimated.
set -euo pipefail
cd "$(dirname "$0")/.."

auto=$(ls -1t results/timing-auto-*.csv 2>/dev/null | head -1 || true)
manual=$(ls -1t results/timing-manual-*.csv 2>/dev/null | head -1 || true)
if [[ -z "$auto" || -z "$manual" ]]; then
  echo "Need both: run 'make demo-auto' and 'make demo-manual' first (CSVs go to results/)." >&2
  exit 1
fi

med() {  # file column
  tail -n +2 "$1" | cut -d, -f"$2" | sort -n \
    | awk '{a[NR]=$1} END{ if (NR%2) print a[(NR+1)/2]; else print (a[NR/2]+a[NR/2+1])/2 }'
}
count() { tail -n +2 "$1" | wc -l | tr -d ' '; }
human=$(med "$manual" 4)

BLOCK=$(cat <<BLK
Measured $(date -u +%Y-%m-%d). Medians in seconds. Raw data: \`$auto\` and \`$manual\`.

Environment: $(nomad version | head -1), $(consul version | head -1), $(docker --version | cut -d, -f1)
Update block: $(grep -E '^\s*(healthy_deadline|progress_deadline|min_healthy_time)' nomad/demo.nomad.hcl | sed -E 's/ +/ /g; s/^ //' | tr '\n' ';' | sed 's/;$//; s/;/; /g')

| Mode | runs | detect (submit to deployment failed) | human (failed to revert issued) | revert (to healthy again) | total |
|------|------|------|------|------|------|
| auto (\`auto_revert = true\`) | $(count "$auto") | $(med "$auto" 3) | n/a | $(med "$auto" 5) | $(med "$auto" 6) |
| manual (\`nomad job revert\`, modelled human reaction = ${human} s) | $(count "$manual") | $(med "$manual" 3) | $(med "$manual" 4) | $(med "$manual" 5) | $(med "$manual" 6) |

"human" is the \`HUMAN_REACTION_SECONDS\` the script waited, not a measured reaction time.
BLK
)

python3 - "$BLOCK" <<'PY'
import re, sys
block = sys.argv[1]
p = "docs/results.md"
s = open(p).read()
new = "<!-- RESULTS:START -->\n" + block + "\n<!-- RESULTS:END -->"
if "<!-- RESULTS:START -->" in s:
    s = re.sub(r"<!-- RESULTS:START -->.*?<!-- RESULTS:END -->", lambda m: new, s, flags=re.S)
else:
    s += "\n" + new + "\n"
open(p, "w").write(s)
PY
echo "Updated docs/results.md. Now fill in the Observations section by hand."
