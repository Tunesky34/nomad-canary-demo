# Timing results

Produced by `make demo-auto`, `make demo-manual`, then `make results` (fills the table below
from the CSVs in `results/`). Proof captured with `make evidence` (see `docs/evidence/`).

<!-- RESULTS:START -->
Not measured yet. Run the demos, then `make results`.
<!-- RESULTS:END -->

## Live proof (fill in)
- Red CI run (bad deploy, Nomad reverted): <link>
- Green CI run after the fix: <link>
- Evidence folder: `docs/evidence/<timestamp>/` (job history shows the reverted version)

## Observations (write these yourself, from what you saw)
- What bounded the automatic rollback (which deadline)?
- What did users see during the bad canary (did the old allocs keep serving)?
- Anything surprising (e.g. whether the revert created its own deployment):
