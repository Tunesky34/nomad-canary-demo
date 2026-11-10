# Nomad canary deploy with automatic rollback (lab)

A demo service where a push to `main` builds an image, pushes it to a lab
registry, and (from Week 2) deploys it to Nomad as a canary that rolls back by
itself when health checks fail.

> Lab only. Nothing here touches real servers or secrets. An engineer applies the
> reviewed PR + runbook to production.

## Status

| Week | Deliverable | State |
|------|-------------|-------|
| 1 | Service with `/health`, Dockerfile, GitHub Actions build + push to lab registry | done in this scaffold |
| 2 | Nomad job (`canary = 1`, `auto_revert = true`, Consul checks) + deploy step that waits for rollout | todo |
| 3 | Deliberate bad deploy, auto rollback vs manual `nomad job revert`, timed | todo |
| 4 | Runbook + `update` block review checklist | todo |

## Layout

```
app/        Node service, tests, Dockerfile
nomad/      Nomad job spec (Week 2)
scripts/    lab-up.sh, smoke-local.sh (deploy.sh, time-rollback.sh later)
docs/       runbook.md, update-block-checklist.md (Week 4)
.github/workflows/deploy.yml
```

## Set up the lab (one command)

Needs an Ubuntu 22.04/24.04 VM you own.

```bash
# Get a runner token: repo (or org) Settings -> Actions -> Runners -> New self-hosted runner
sudo RUNNER_URL=https://github.com/<intern-org>/<repo> \
     RUNNER_TOKEN=<registration-token> \
     ./scripts/lab-up.sh
```

This installs Docker, Nomad and Consul (single-node dev config), starts a
`registry:2` container on `localhost:5000`, and registers a self-hosted runner
labelled `lab`. Leave `RUNNER_URL`/`RUNNER_TOKEN` unset to skip the runner.

Why a self-hosted runner: GitHub-hosted runners cannot reach the lab registry,
Nomad or Consul.

## The service

| Endpoint | Behaviour |
|----------|-----------|
| `GET /health` | `200 {"status":"ok"}`; `500` when `FAIL_HEALTH=true` |
| `GET /` | service name and version |

Env vars (used for the Week 3 demo):

| Var | Effect |
|-----|--------|
| `FAIL_HEALTH=true` | `/health` returns 500 |
| `CRASH_ON_START=true` | process exits immediately |
| `STARTUP_DELAY_MS=N` | delay before listening (to exceed `healthy_deadline`) |
| `APP_VERSION` | baked in at build from the git SHA |

## Verify Week 1

```bash
make test     # unit tests (Node 20+)
make smoke    # builds the image, checks /health returns 200 and 500
```

Then push to `main` and confirm in the Actions tab that `test` and
`build-and-push` pass, and:

```bash
curl http://localhost:5000/v2/demo/tags/list   # shows the git SHA tag
```

## Conventions

- Images are tagged with the full git SHA, never `:latest`. If the image string
  does not change, Nomad sees no diff and starts no deployment.
