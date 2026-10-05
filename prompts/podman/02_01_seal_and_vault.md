# Prompt podman/02.01 — Seal node and Vault node

Read `prompts/podman/00_01_brief.md` first. Requires 01.01.

## Why this prompt exists

The demo needs a Vault, and the old one was configured by hand and lives
outside the repository. vault_reference showed the shape that survives
volume loss and cold starts: a Shamir-sealed `vault-s` holding a Transit key,
an application Vault that auto-unseals through it, and a bootstrap that
compares the files on disk with the storage instead of guessing.

## Goal

From empty volumes, `make vault-bootstrap` produces an unsealed vault-s and
an unsealed, active vault-1. After a stop, `make vault-up` brings back the
same state without re-initializing anything, with exactly one manual secret:
the vault-s unseal key, read from `.secrets/vault/seal-init.json`.

## Reference

- `vault_reference/scripts/vault-bootstrap.sh` (the four-case table, lock
  directory, write-in-place token file)
- `vault_reference/scripts/vault-unseal.sh`
- `vault_reference/compose/seal/compose.yaml` and `compose/primary/` (the
  `vault-s` and `vault-1` services only; no rotators, agents or sidecars)
- `vault_reference/vault-s/config-s.hcl`, `vault-1/config.hcl`

## Deliverables

1. `vault/vault-s/config.hcl`: Raft at `/vault/file`, node id `vault-s`, TLS
   1.3 listener, no seal stanza (Shamir), `api_addr https://vault-s:8200`.
2. `vault/vault-1/config.hcl`: Raft, node id `vault-1`, TLS 1.3 listener,
   `seal "transit"` pointing at `https://vault-s:8200`, key `autounseal`,
   `tls_ca_cert` the chain. No token in the file. Lease defaults 1h/24h.
3. `vault/policies/autounseal.hcl`: encrypt/decrypt on
   `transit/{encrypt,decrypt}/autounseal` only.
4. `compose/seal/compose.yaml`: `srot-vault-s`, hostname `vault-s`,
   `user: "100:1000"`, `cap_drop: [ALL]`, `no-new-privileges`, entrypoint
   `scripts/vault-server.sh`, volumes `vault-s-data`, `vault-s-audit`
   (labelled persistent), port `127.0.0.1:${SROT_PORT_VAULT_S}:8200`,
   healthcheck that is healthy whenever the process answers (sealed and
   uninitialized are normal), network `srot-internal` (external).
5. `compose/vault/compose.yaml`: `srot-vault-1`, same hardening, the Transit
   token as a file mount from `.secrets/vault/transit-token`, no
   `VAULT_TOKEN` in the environment. `VAULT_LICENSE` passed through (empty
   is fine on Community).
6. `scripts/vault-bootstrap.sh` (idempotent, lock dir under
   `.secrets/vault/`):
   seal: start, wait reachable, initialize (1/1) per the table, unseal,
   `transit/` mount, key `autounseal`, policy from file, file audit device,
   periodic orphan Transit token (`-period=720h`) written in place to
   `.secrets/vault/transit-token` only when the existing one is rejected.
   vault: start (force-recreate only when the token was replaced), wait
   reachable, initialize with `-recovery-shares=1 -recovery-threshold=1`
   per the table, wait unsealed and active, enable the file audit device.

   | Init file | Storage | Action |
   | --- | --- | --- |
   | absent | uninitialized | initialize |
   | present | initialized | continue |
   | present | uninitialized | stop: "saved credentials but no storage" |
   | absent | initialized | stop: "initialized but credentials missing" |

   Mounts, auth methods and policies other than `autounseal` belong to
   Terraform (03.01).
7. `scripts/vault-unseal.sh`: unseal vault-s from the init file; idempotent;
   loud when the key does not match the storage.
8. `scripts/vault-status.sh`: table of both nodes: container state,
   initialized, sealed, HA mode, Raft applied index, version. A node whose
   container does not exist shows "not created".
9. Make targets: `vault-bootstrap`, `unseal`, `seal-up` (start + unseal),
   `seal-down`, `vault-up` (seal-up, then vault-1, wait active),
   `vault-down`, `vault-status`, `vault-recreate` (recreate vault-1 keeping
   its volume), `vault-login` (prints an `export VAULT_ADDR=… VAULT_CACERT=…`
   line for the user's shell; never prints a token).
10. `scripts/verify.sh` behind `make verify`, sectioned so later prompts
    append. Section "vault": both containers healthy, vault-s unsealed,
    vault-1 unsealed and active, its seal type is `transit`, certificate
    chain verifies, audit device enabled on both.

## Design rules

- Healthchecks describe the process, not readiness. Ordering is Make's job.
- Host tooling talks to published loopback ports and verifies TLS with
  `vault-tls/ca-chain.pem`.
- Root tokens are used only by the bootstrap and by `scripts/tf.sh` in this
  lab, read from `.secrets/vault/<cluster>-init.json`. Say so in comments.

## Validation

```bash
make vault-bootstrap
make vault-status                       # both unsealed, vault-1 active
make verify
curl -s --cacert vault-tls/ca-chain.pem https://127.0.0.1:18200/v1/sys/seal-status | jq -r .type   # transit

# Idempotence
make vault-bootstrap                    # changes nothing, exits 0

# Cold start: vault-1 cannot unseal until vault-s is unsealed
make vault-down && make vault-up && make verify

# Seal dependency is real. Vault 2.x does not start sealed when the Transit
# seal is unreachable: it exits ("error parsing Seal configuration") and the
# restart policy loops it until vault-s is back.
make seal-down
podman restart srot-vault-1 && sleep 15
podman logs --tail 3 srot-vault-1 2>&1 | grep -c 'error parsing Seal configuration'   # ≥ 1
make vault-up && make verify            # recovers without re-init

# Persistence
make vault-recreate && make verify
```
