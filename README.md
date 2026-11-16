# Nomad canary deploy with automatic rollback (lab)

A push to `main` builds an image, pushes it to a lab registry, deploys it to Nomad as a
canary, waits for the rollout, and **fails the CI run if the rollout fails**. A deploy
that breaks health checks is rolled back by Nomad on its own (`auto_revert`).

> Lab only. Nothing here touches real servers or secrets. An engineer applies the
> reviewed PR + runbook to production (see `docs/PR_DESCRIPTION.md`).

## Status

| Week | Deliverable | State |
|------|-------------|-------|
| 1 | Service with `/health`, Dockerfile, Actions build + push to lab registry | done |
| 2 | Nomad job (`canary = 1`, `auto_revert = true`, Consul checks) + deploy step that waits for the rollout | done, **verify in your lab** |
| 3 | Bad deploy, auto rollback vs manual `nomad job revert`, timed | scripts + demo script ready; **run it and fill `docs/results.md`** |
| 4 | Runbook + `update` block review checklist | `docs/runbook.md`, `docs/update-block-checklist.md` |

## Layout

```
app/                       Node service, tests, Dockerfile
nomad/demo.nomad.hcl       canary + auto_revert + Consul check
deploy.env                 failure switches the demo flips via a commit
scripts/lab-up.sh          one-command lab setup
scripts/deploy.sh          submit job, WAIT for deployment, exit 1 if it failed
scripts/time-rollback.sh   time auto vs manual rollback (3 runs, medians)
scripts/audit-update-blocks.sh   read-only audit of every service job's update block
tests/                     deploy.sh + audit tests (fake nomad, no cluster needed)
docs/                      runbook, review checklist, demo script, results, PR text
.github/workflows/deploy.yml
```

## Set up the lab (one command)

Ubuntu 22.04/24.04 VM you own:

```bash
# token: repo/org Settings -> Actions -> Runners -> New self-hosted runner (expires in ~1 hour)
sudo RUNNER_URL=https://github.com/<intern-org>/<repo> \
     RUNNER_TOKEN=<registration-token> \
     ./scripts/lab-up.sh
```

Installs Docker, Nomad, Consul (single-node lab config), a `registry:2` on
`localhost:5000`, and a self-hosted runner labelled `lab`. Log out/in afterwards so your
user gets the docker group. GitHub-hosted runners cannot reach the lab, hence self-hosted.

## Troubleshooting the lab

```bash
systemctl status nomad --no-pager -l ; journalctl -u nomad -n 50 --no-pager
curl -s http://127.0.0.1:4646/v1/status/leader      # prints "127.0.0.1:4647" when healthy
nomad node status -self | grep -iE 'status|docker'   # node ready, docker driver healthy
```

- **Nomad restarts in a loop**: the journal names the bad config line. Fix
  `/etc/nomad.d/nomad.hcl`, then `sudo systemctl restart nomad`. Re-running `lab-up.sh`
  rewrites the config and restarts both services.
- **Leader/raft errors after an IP change** (lab only, wipes Nomad state):
  `sudo systemctl stop nomad && sudo rm -rf /opt/nomad/data/* && sudo systemctl start nomad`
- The Nomad UI is on loopback only. From another machine use
  `ssh -L 4646:localhost:4646 <vm>`.

## Verify

```bash
make test       # app tests + deploy.sh tests + audit tests (needs node 20+, jq)
make smoke      # builds the image, /health must be 200 and 500 (needs docker)
```

Then push to `main`. The workflow runs `test`, `build-and-push`, `deploy`. The first
deploy creates version 1 (no canary is possible yet; it becomes the first *stable*
version). Every later push deploys as a canary.

## How the rollout works

- Job: `count = 2`, `canary = 1`, `health_check = "checks"` (Consul HTTP `/health`),
  `healthy_deadline = 45s`, `progress_deadline = 90s`, `auto_revert = true`,
  `auto_promote = true`. Restart and reschedule are bounded so a crash-loop fails fast.
- `scripts/deploy.sh` submits with `-detach`, then polls the deployment for **that job
  version** until it is `successful` (exit 0), `failed`/`cancelled` (exit 1) or times out
  (exit 2). After a failure it prints diagnostics and reports the auto-revert result.
- Exit 1 makes the CI job red even though Nomad already restored the old version. That is
  intended: a failed rollout is still a failed release.
- If Nomad creates no deployment for a new version, the script exits 2 rather than
  reporting an unverified success.

## Demo, timing, and the break-it-on-purpose switches

See `docs/demo-script.md`. Short version:

```bash
sed -i 's/FAIL_HEALTH=false/FAIL_HEALTH=true/' deploy.env
git commit -am "demo: break health" && git push origin main    # canary fails, rolls back, run goes red
GOOD_IMAGE=localhost:5000/demo:<sha> make demo-auto
GOOD_IMAGE=localhost:5000/demo:<sha> HUMAN_REACTION_SECONDS=60 make demo-manual
```

| Switch (`deploy.env`) | Effect |
|-----------------------|--------|
| `FAIL_HEALTH=true` | `/health` returns 500 |
| `CRASH_ON_START=true` | process exits immediately |
| `STARTUP_DELAY_MS=N` | listens late; use a value above `healthy_deadline` |

## When a deploy goes bad / reviewing a job

- `docs/runbook.md`: what to do, in order
- `docs/update-block-checklist.md`: review any job spec; `make audit` flags risky jobs on a cluster

## Conventions

- Images are tagged with the full git SHA, never `:latest`.
- One `update` block per group, defined at group level (it overrides job level).
