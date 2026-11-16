# Live demo script (about 10 minutes)

Goal: show a broken deploy rolling back with nobody touching it, then compare with a
manual `nomad job revert`.

## Before you start
- `make lab-up` done, runner online (GitHub: Settings, Actions, Runners shows "Idle").
- A good version deployed and healthy: push any commit to `main` and wait for green.
- Open three terminals: `watch -n2 nomad job status demo`, Nomad UI (`:4646`), Actions tab.
- Note the good image: `nomad job inspect -json demo | jq -r '(.Job//.)|.TaskGroups[].Tasks[].Config.image'`

## Part 1: automatic rollback
1. Break it with an ordinary commit:
   ```bash
   sed -i 's/FAIL_HEALTH=false/FAIL_HEALTH=true/' deploy.env
   git commit -am "demo: break health checks on purpose" && git push origin main
   ```
2. Narrate what appears: tests pass, image builds and pushes, `deploy` starts,
   a canary alloc appears (3 allocs: 2 old, 1 canary), the canary's Consul check goes
   **critical**, after about `healthy_deadline` the deployment goes **failed**, Nomad creates a new
   job version with the old spec, the canary is stopped, the **Actions run goes red**.
3. Show the service never stopped answering: `curl localhost:<port>/health` on the old allocs.
4. Show history: `nomad job history demo` (the revert is a new version).

## Part 2: the fix
```bash
git revert HEAD --no-edit && git push origin main    # restores FAIL_HEALTH=false
```
Run goes green, canary promoted, rolled out.

## Part 3: second failure mode (optional)
Set `CRASH_ON_START=true` in `deploy.env` and push. Shows a crash-looping task
failing the deployment instead of being hidden by restarts.

## Part 4: timings
```bash
GOOD_IMAGE=<good image> make demo-auto
GOOD_IMAGE=<good image> HUMAN_REACTION_SECONDS=60 make demo-manual
```
Copy the medians into `docs/results.md`.

## Reset
Push a commit with `deploy.env` back to `FAIL_HEALTH=false`, or `nomad job stop -purge demo`.
