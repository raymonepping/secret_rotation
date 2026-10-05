# Prompt podman/07.01 — Foolproof machine identity: rotator + agent, as in Durin

Read `prompts/podman/00_01_brief.md` first. Requires 06.01.

## Why this prompt exists

04.01 gave the API a Vault Agent, but its AppRole secret-id was issued by
hand (`make app-credentials`) with `secret_id_ttl = 0`: it never expires,
nobody rotates it, and if it is destroyed the API stays dead until a human
notices. Project Durin solved this properly (a rotator sidecar that keeps the
secret-id valid on Vault's own answer, an agent with a watchdog, a dedicated
narrowly-scoped rotator identity) and vault_reference generalised it. This
repo should heal the same way.

There is also a latent Durin bug waiting here: vault-1's `max_lease_ttl` is
24h, and AppRole caps every secret-id at the mount's effective maximum. A
role that declares 90 days would silently get 24 hours.

## Goal

The API identity's secret-id expires (90 days), is rotated automatically
before it does, and every credential failure (dead token, destroyed
secret-id, both at once, the rotator's own credential gone) heals without a
human — or, for the last one, with exactly one make target.

## Reference

- `HashiCorp/project_durin/compose/vault/vault-rotator/rotator.sh`,
  `healthcheck.sh`, `compose/vault/compose.yaml` (vault-rotator,
  durin-vault-agent, volume-init), `terraform/vault-platform/auth.tf` (the
  mount `tune` and why), `policies.tf` (`durin-rotator`)
- `Personal/vault_reference/compose/common/rotator/` (multi-role version,
  credentials from a bind-mounted directory instead of `.env`, `rotate-now`
  marker), `terraform/vault-platform/agents.tf`, `scripts/rotator-bootstrap.sh`,
  `agents-status.sh`, `agents-recover.sh`, `test-rotation.sh`

## Deliverables

1. `terraform/vault-platform`:
   - Tune `auth/approle`: `max_lease_ttl = "2160h"` (90 days), with the Durin
     comment. Without it the 90-day secret-id silently lives 24h.
   - `secret-theatre-api`: `secret_id_ttl` from a variable, default 7776000.
   - Role `secret-theatre-rotator`: policy that may only read the API role's
     role-id, create, look up and destroy its secret-ids; `token_ttl = 300`,
     `token_max_ttl = 600`, `secret_id_ttl = 0` (it is the one bootstrap
     credential), token and secret-id bound to the `srot-internal` CIDR.
2. `compose/app/rotator/{rotator.sh,healthcheck.sh}` from vault_reference's
   common rotator (same algorithm: Vault's reported expiry, rotate below 1/3
   of the real life, one secret-id per rotation, destroy the replaced one,
   loud when a cap shortens the life, `rotate-now` marker).
3. `compose/app/compose.yaml`: `srot-rotator` (Vault image, uid 100, read-only
   root, rotator credentials bind-mounted read-only from
   `.secrets/vault/rotator/`, writes `/run/approle/secret-theatre-api/` in
   the persistent `approle-api` volume, `CHECK_INTERVAL_SECONDS=60`,
   healthcheck). 60s, not vault_reference's 300s: a pass is one login and
   one lookup, and the interval bounds how long a destroyed secret-id leaves
   the API dead. The agent caps its login backoff at 30s (default 5 min). The agent mounts that directory read-only and depends on the
   rotator being healthy. `volume-init` prepares both volumes.
4. `scripts/rotator-bootstrap.sh` behind `make rotator-bootstrap`: delivers
   the rotator's role-id and secret-id (root token, lab), idempotent. It
   replaces `make app-credentials`. Migration: the hand-issued, non-expiring
   API secret-id under `.secrets/vault/approle-api/` is destroyed in Vault (by
   accessor) and the directory moved to `.secrets/legacy/`.
5. `make agents-status` (identity, agent health, token TTL, secret-id expiry,
   last rotation, rotator health), `make agents-recover` (re-deliver rotator
   credentials if it cannot log in, restart agents Vault rejects),
   `make rotate-now`, `make rotation-test`.
6. `scripts/test-rotation.sh` (changes state), each case ending with the API
   serving a dynamic credential again:
   1. the agent's token is revoked → watchdog restarts the agent, new token;
   2. `make rotate-now` → new secret-id, old one destroyed, agent unaffected;
   3. the secret-id is destroyed **and** the token revoked (worst case) →
      rotator re-issues, agent logs in with it, no human;
   4. the rotator's own secret-id is destroyed → `make agents-recover` heals it.
7. `make verify` app section: rotator healthy; the API secret-id's real
   lifetime is ≥ 89 days (proves the mount tune); the rotator token cannot
   read `database/creds/*`. `make doctor`: rotator checks with fixes.
8. Docs: README (identity section, targets), `compose/README.md` rows,
   `CLAUDE.md`, CHANGELOG, `docs/STATE.md`.

## Design rules

- The rotator decides on Vault's answer, never on a local schedule.
- The only credential a human (or `make`) hands over is the rotator's.
  Everything the API uses is issued and rotated by machines.
- The API process is never restarted to recover: it reads the token file per
  request.
- Files shared between containers are replaced atomically.

## Validation

```bash
make tf-platform && make tf-plan-all
make rotator-bootstrap && make app-up
make agents-status                 # secret-id expires in ~90 days, rotator healthy
make verify
make rotation-test                 # all four cases heal
make down && make up && make verify
```
