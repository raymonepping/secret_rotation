# secret_rotation — Vault Secret Theatre

Three Vault secret lifecycles (dynamic, static, root rotation) against
PostgreSQL. Podman + Make + Terraform, modelled on `../vault_reference`.

## Rules

- Operate through `make` (`make help`). Compose only via
  `scripts/compose.sh <stack> …`; Terraform only via `scripts/tf.sh <root> …`.
- Check with `make verify` (and `make doctor`) before and after a change;
  `make tf-plan-all` must stay clean.
- No tokens or passwords in tracked files, Compose files or `.env` values the
  app reads. The API gets its token from the Vault Agent's file; the rotator
  keeps the agent's secret-id valid; the seal plane does the same for vault-1's
  Transit token. The only credentials handed over are the two rotators'
  (`make rotator-bootstrap`). Never issue a secret-id or seal token by hand.
  Secrets live in `.secrets/`.
- After touching identity, run `make rotation-test` (it breaks credentials on
  purpose and must heal all five cases).
- After moving any bind-mounted file, recreate the containers (`make up`):
  a container keeps its old mount path and fails on its next restart.
  `make doctor` flags it.
- No `-tls-skip-verify`, `VAULT_SKIP_VERIFY` or `NODE_TLS_REJECT_UNAUTHORIZED=0`.
- Filter every `podman` command by `srot-`. Never touch `vref-*`, `demo-*` or
  other projects' containers. Never prune volumes; `make clean-slate` is the
  only path that removes them.
- Scripts are bash. Do not pipe into `grep -q` under `pipefail`.
- UI changes follow `DESIGN.md`; colour only for state. Lane behaviour
  (buttons, timers, API calls) is part of the demo: change it deliberately.
- Do not commit, tag or push unless asked. `commit_gh` stages everything.

## Where things are

- Design system: `DESIGN.md`. Stacks and persistence: `compose/README.md`.
- Build log and lessons: `docs/STATE.md`. Prompts: `prompts/podman/`.
