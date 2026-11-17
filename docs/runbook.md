# Runbook: a deploy went bad, what do I do?

Applies to Nomad service jobs deployed with an `update` block. Commands assume
`NOMAD_ADDR` points at the right cluster. Replace `<job>` with the job name
(`demo` in the lab).

**First, stay calm and look before you touch anything.** With `canary = 1`, most
traffic is usually still on the old version. Check before you revert.

## 0. How bad is it? (30 seconds)

```bash
nomad job status <job>
```

Look at:
- **Latest Deployment**: `Status` (`running`, `failed`, `successful`) and its description.
- **Allocations**: which job `Version` each alloc runs, and whether any are `failed`/unhealthy.
- **Deployed** table: `Canaries`, `Placed`, `Healthy`, `Unhealthy` per group.

| What you see | Meaning | Go to |
|---|---|---|
| Deployment `running`, canary unhealthy | Rollout in progress and going wrong | 2 |
| Deployment `failed`, a newer version appeared and is `successful` | Auto-revert worked | 3 |
| Deployment `failed`, nothing reverted | `auto_revert` off, or no stable version to go back to | 4 |
| Deployment `successful` but the service is broken | Health checks did not catch it | 4, then fix the check (see checklist) |

## 1. Find out why it failed

```bash
nomad job deployments <job>                 # list deployments, newest first
nomad deployment status <deployment-id>     # per-group counts + failure reason
nomad job allocs <job>                      # find the canary / unhealthy alloc ID
nomad alloc status <alloc-id>               # task events: OOM, image pull error, exit code
nomad alloc logs -stderr <alloc-id>         # app output
nomad alloc logs <alloc-id>
curl -s $CONSUL_HTTP_ADDR/v1/health/checks/<service-name> | jq '.[] | {Node, Name, Status, Output}'
```

Common causes: image tag not in the registry (pull error), app crashes on start,
`/health` returns non-200, health check slower than `healthy_deadline`,
missing env var or secret.

## 2. Rollout still running and clearly bad: stop it now

```bash
nomad deployment fail <deployment-id>
```

If the job has `auto_revert = true` this also triggers the revert. Then go to 3.
If it does not, go to 4.

## 3. Auto-revert is on: confirm it finished

```bash
nomad job history <job>             # a new top version should carry the last Stable=true spec
nomad job status <job>              # latest deployment successful, all allocs running
```

Verify with the checks in step 5. Do **not** revert again by hand if this looks correct.

## 4. Revert by hand

```bash
nomad job history <job>             # pick the newest version with Stable = true
nomad job revert <job> <version>    # re-submits that version's spec
nomad job deployments <job>         # newest deployment is the revert; watch it
nomad deployment status <deployment-id>
```

Notes:
- Pick the last **Stable = true** version. A version only becomes stable after a
  successful deployment. If none exists (first-ever deploy), there is nothing safe to go
  back to: fix forward, or stop the job.
- Nomad only keeps a limited number of old versions (server setting
  `job_tracked_versions`, default 6). If the good version has aged out, redeploy the
  last good image tag instead (`IMAGE=<old tag> ./scripts/deploy.sh` in the lab; your
  normal deploy process on real servers).
- If the job spec lives in git, **also revert the commit**, otherwise the next pipeline
  run redeploys the bad version.

## 5. Verify recovery

```bash
nomad job status <job>                                           # all allocs running, latest deployment successful
curl -s $CONSUL_HTTP_ADDR/v1/health/service/<service-name>?passing=true | jq length   # = expected count
curl -fsS http://<service-address>/health                        # 200
```

## 6. Things revert will NOT fix

- **Database migrations / schema changes**: reverting the app does not undo the schema.
  Stop and involve the service owner before reverting anything stateful.
- **Config in Consul KV / Vault / external systems** changed alongside the deploy.
- **Bad data already written** by the new version.

## 7. After the incident

1. Write a short post-mortem: what shipped, how it was detected, how long it took.
2. If the job had `auto_revert` off or a weak health check, fix it. Use
   `docs/update-block-checklist.md` and run `make audit`.
3. Add the failure to the demo/test list if the existing health check missed it.
4. Tell the team what version is live and why.
