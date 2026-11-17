# PR: Deploy pipeline with canary and automatic rollback on Nomad (lab demo)

## What
A push to `main` builds an image, pushes it to a lab registry, deploys it to Nomad as a
canary, **waits for the rollout**, and fails the CI run if the rollout fails. A deployment
that fails health checks is rolled back automatically by Nomad (`auto_revert`).

## Why
Our rollback plan relies on Nomad's job revert, some services have `auto_revert` off, and
nobody has practised a bad deploy end to end.

## What is in it
- `app/` Node demo service, `/health`, Dockerfile, tests
- `.github/workflows/deploy.yml` test, build, push, deploy
- `nomad/demo.nomad.hcl` canary + `auto_revert` + Consul checks
- `scripts/deploy.sh` waits for the deployment to finish; exit 1 on failed rollout
- `scripts/time-rollback.sh` times auto vs manual rollback
- `scripts/audit-update-blocks.sh` read-only audit of every service job's update settings
- `docs/runbook.md`, `docs/update-block-checklist.md`, `docs/demo-script.md`, `docs/results.md`

## How to review / re-run
1. `make lab-up` (see README), `make test`
2. Follow `docs/demo-script.md`

## Tested
- App unit tests, `deploy.sh` logic against a fake nomad CLI (success / failed+revert / no change),
  audit filter against sample specs
- Live demo in the lab: **fill in** (date, link to the failed Actions run, `docs/results.md`)

## Not tested / for the engineer applying this
- Lab config is single-node and insecure on purpose; do not copy `lab-up.sh` to real servers
- Real clusters: ACLs/tokens, TLS, registry auth, and real `datacenters` names are not covered
- Run `make audit` against real servers (read-only) to find jobs with `auto_revert` off
