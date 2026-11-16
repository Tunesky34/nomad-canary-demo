# Checklist: reviewing a Nomad job's `update` settings

Use on every PR that adds or changes a service job. A "no" on a **Must** item blocks the
merge unless there is a written reason. Run this first to see what is really in effect:

```bash
nomad job inspect -json <job> | jq '(.Job // .) | .TaskGroups[] | {group: .Name, count: .Count, update: .Update}'
# whole cluster, read-only, risky rows flagged:
./scripts/audit-update-blocks.sh
```

Durations in that JSON are nanoseconds (45s = 45000000000).

## Must

| # | Check | Why | Looks like |
|---|-------|-----|-----------|
| 1 | `auto_revert = true` | Default is **false**: a failed deploy just stays broken | `auto_revert = true` |
| 2 | `health_check = "checks"` and the group has a `service` with a real check | `task_states` only means "process is running", not "app works" | HTTP `/health` that exercises the app, not just the port |
| 3 | `canary >= 1` (or `max_parallel` small) | `canary = 0` replaces allocs straight away, with no safe comparison | `canary = 1` |
| 4 | `count >= 2` for anything with a canary | With one alloc a canary is the whole service | `count = 2` |
| 5 | `min_healthy_time <= healthy_deadline <= progress_deadline` | Inverted values make deployments fail instantly or hang | 10s / 45s / 90s in the lab |
| 6 | `progress_deadline` is not `0` | `0` disables the timer, so a stuck deploy never fails and never reverts | non-zero |
| 7 | There is a way to get a **stable** version | `auto_revert` reverts to the last *stable* version; the first-ever deploy has none | deploy a good version first |
| 8 | Image tag is immutable (git SHA), not `:latest` | Same string = no diff = no deployment; revert may pull the wrong bits | `image = "…:<sha>"` |

## Should

| # | Check | Why |
|---|-------|-----|
| 9 | Group-level vs job-level `update`: only one is defined, or they agree | A group-level block silently overrides the job-level one |
| 10 | `healthy_deadline` is longer than the app's real worst-case startup | Too short = false failures; too long = slow rollback |
| 11 | `restart` / `reschedule` are bounded (`mode = "fail"`, no unlimited reschedule) | Endless restarts hide a crash-loop and delay the "unhealthy" verdict |
| 12 | `check_restart` is understood and deliberate | It can kill/restart the canary before the deployment judges it |
| 13 | `auto_promote` matches intent | `true` = promotes when the canary is healthy; `false` = someone must run `nomad deployment promote` |
| 14 | `kill_timeout` and shutdown behaviour match the app | Slow shutdown stretches both rollout and revert |
| 15 | Enough old versions are retained to revert | Server `job_tracked_versions` (default 6) |

## Ask the author

| # | Question |
|---|----------|
| 16 | Does this release include a DB migration or other change a revert cannot undo? If yes, what is the plan? |
| 17 | Has anyone broken this service on purpose in a lab and watched it roll back? |
| 18 | Where is the runbook link for this service? |

## Reviewer sign-off

```
Job: ________   Reviewer: ________   Date: ________
Must items 1-8 pass: [ ]   Exceptions (with reason): ______________________
```
