# Prompt podman/08.01 — The seal plane heals itself too

Read `prompts/podman/00_01_brief.md` first. Requires 07.01.

## Why this prompt exists

07.01 made the API's identity self-healing. The other machine credential in
the stack is still a file: vault-1's Transit seal token, issued once by
`make vault-bootstrap` into `.secrets/vault/transit-token`. It is periodic
and vault-1 renews it, so it lives — until it is revoked, or vault-1 is down
longer than its period. Then vault-1 cannot unseal after its next restart and
crash-loops with a message that looks like a healthcheck flake (see the
memory "Vault transit token expiry crash-loops nodes"). Nobody notices until
then. vault_reference moved this token to a seal-plane agent and rotator;
this repo does the same.

## Goal

vault-1 starts with a Transit token that a Vault Agent on vault-s keeps
fresh, the agent's secret-id is rotated like the API's, a revoked seal token
is detected while vault-1 still runs, and recovery is one make target.

## Reference

- `vault_reference/terraform/vault-seal/` (approle mount tune, rotator and
  `seal-autounseal` roles, periodic tokens; bootstrap keeps owning transit,
  key and `autounseal` policy so a destroy can never remove the seal)
- `vault_reference/compose/seal/compose.yaml` (rotator, agent, sink volume
  shared with the nodes), `compose/seal/agents/seal-autounseal/config.hcl`
- `vault_reference/scripts/vault-server.sh` (agent sink first, verified
  against vault-s; bootstrap file as fallback), `seal-up.sh`,
  `seal-token-status.sh`, `vault-common.sh: ensure_seal_token_volume`

## Deliverables

1. Shared machinery: move the rotator to `compose/common/rotator/` and the
   agent entrypoint to `compose/common/agent/entrypoint.sh`; both planes use
   them. No copies.
2. `terraform/vault-seal` (state in `.secrets/terraform/`, vault-s, seal root
   token through `scripts/tf.sh`): `auth/approle` tuned to 2160h; role
   `seal-rotator` (policy: only `seal-autounseal`'s secret-id paths, CIDR-
   bound, `secret_id_ttl = 0`); role `seal-autounseal` (`token_policies =
   ["autounseal"]`, `token_period = 86400`, `secret_id_ttl` 90 days, CIDR-
   bound).
3. `compose/seal/compose.yaml`: `srot-seal-rotator`, `srot-seal-agent` (sink
   `transit-token` mode 0640 in volume `seal-token`), `volume-init`. The
   vault stack mounts `seal-token` (external, created up front with compose
   labels so either stack can start first).
4. `scripts/vault-server.sh`: prefer `/run/secrets/seal/transit-token`,
   checked against vault-s; use the bootstrap file only when vault-s
   *rejects* the sink token; when vault-s cannot be reached, use the sink
   token and let the seal retry.
5. `scripts/seal-up.sh` behind `make seal-up`: vault-s, unseal, renew the
   bootstrap fallback token, start rotator and agent when their credential
   exists, wait for the agent.
6. `make tf-seal` (part of `tf-all`), `make rotator-bootstrap` delivers both
   planes' rotator credentials, `make seal-token-status` (the token the
   running vault-1 process holds, checked against vault-s),
   `agents-status` / `agents-recover` / `rotate-now ROLE=` cover both planes,
   `make vault-recreate` uses the agent's token afterwards.
7. `make rotation-test` gets case 5: the seal token vault-1 runs on is
   revoked → vault-1 keeps serving, `seal-token-status` flags it, the seal
   agent has a fresh token, `make vault-recreate` restarts vault-1 on it,
   `seal-token-status` is clean, the lanes work.
8. `make verify`: vault-1 runs on the agent's token (not the bootstrap one);
   seal rotator and agent healthy; the seal-autounseal secret-id lives ≥ 89
   days. `make doctor`: seal-token checks with fixes.
9. Docs: README identity section (both planes), `compose/README.md`, CLAUDE,
   CHANGELOG, `docs/STATE.md`.

## Design rules

- Bootstrap keeps owning what must exist before anything else: transit,
  the key, the `autounseal` policy, the fallback token. Terraform never
  manages them.
- A dead token in the sink must never crash-loop vault-1: the server
  entrypoint verifies before it uses.
- The token is read once at vault-1's start: a replaced token is used at the
  next restart, never by restarting vault-1 automatically.

## Validation

```bash
make tf-all && make tf-plan-all
make rotator-bootstrap && make seal-up && make vault-recreate
make seal-token-status           # vault-1: valid, source: agent
make agents-status
make verify
make rotation-test               # five cases heal
CONFIRM=DELETE make clean-slate && make bootstrap
make down && make up && make verify
```
