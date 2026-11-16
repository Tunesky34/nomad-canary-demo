# Timing results

Fill in after running `make demo-auto` and `make demo-manual` in the lab. Raw CSVs are
written to `results/`. Medians over 3 runs, in seconds.

Environment: Nomad ____  Consul ____  Docker ____  VM ____ vCPU / ____ GB
`update` block: healthy_deadline = ____  progress_deadline = ____  min_healthy_time = ____

| Mode | detect | human | revert | total |
|------|--------|-------|--------|-------|
| auto (`auto_revert = true`) | | n/a | | |
| manual (`nomad job revert`, human reaction = ____ s) | | | | |

## Observations
- What bounded the automatic rollback (which deadline)?
- What did users see during the bad canary (old allocs kept serving?):
- Anything surprising (e.g. revert created or did not create a deployment):
