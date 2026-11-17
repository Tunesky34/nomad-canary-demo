# Timing results

Produced by `make demo-auto`, `make demo-manual`, then `make results` (fills the table below
from the CSVs in `results/`). Proof captured with `make evidence` (see `docs/evidence/`).

<!-- RESULTS:START -->
Measured 2026-11-17. Medians in seconds. Raw data: `results/timing-auto-20261117-103401.csv` and `results/timing-manual-20261117-103706.csv`.

Environment: Nomad v2.1.1, Consul v2.1.0, Docker version 29.8.2
Update block: min_healthy_time = "10s"; healthy_deadline = "45s"; progress_deadline = "90s"

| Mode | runs | detect (submit to deployment failed) | human (failed to revert issued) | revert (to healthy again) | total |
|------|------|------|------|------|------|
| auto (`auto_revert = true`) | 3 | 48 | n/a | 4 | 51 |
| manual (`nomad job revert`, 60 s modelled reaction) | 3 | 47 | 63 | 1 | 111 |

"human" is the observed failed-to-revert-command interval. `HUMAN_REACTION_SECONDS=60`
was configured; the 63 s median also includes failure-observation/polling granularity.
This models a response delay, not a measured human reaction.
<!-- RESULTS:END -->

## Live proof
- Red CI run: [44055796528](https://github.com/Tunesky34/nomad-canary-demo/actions/runs/44055796528) — job version 7 failed health checks; Nomad reverted to the stable version 6 spec in successful version 8.
- Green CI run after restoring `FAIL_HEALTH=false`: [44058586859](https://github.com/Tunesky34/nomad-canary-demo/actions/runs/44058586859).
- Nomad evidence: `docs/evidence/20261117-103346/` (history, deployment status, allocations, and failed canary events).

## Observations
- The `healthy_deadline = 45s` bounded the bad canary; Nomad reported it had not met `min_healthy_time = 10s` by that deadline. CI observed failure 49 seconds after submission. The 90-second progress deadline did not bind.
- Nomad placed one canary while the two existing allocations remained the stable version; after rollback, both healthy allocations and two passing Consul checks were present. No client-traffic probe ran during the failure, so user-visible requests were not measured directly.
- Auto-revert created a new successful deployment (version 8) using the prior stable version 6 spec; the failed version 7 remained unstable. The CI run correctly stayed red even though Nomad restored service.
