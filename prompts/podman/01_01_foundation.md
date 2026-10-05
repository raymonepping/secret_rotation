# Prompt podman/01.01 — Foundation

Read `prompts/podman/00_01_brief.md` first.

## Why this prompt exists

Today there is one `compose.yml` with a hardcoded password, a bind mount
outside the repository and no Vault at all. Starting the demo means three
terminals and a Vault somebody configured by hand. This prompt builds the
skeleton the later prompts fill in. It starts nothing.

## Goal

`make help`, `make check`, `make network`, `make gen-certs`,
`make ports-check` and `make compose-config` work on a clean checkout.

## Reference

- `vault_reference/Makefile` (structure, `help` awk, `STACK_TARGETS` macro)
- `vault_reference/scripts/compose.sh`, `podman-check.sh`, `network.sh`,
  `ports-check.sh`, `vault-common.sh`, `vault-server.sh`

## Deliverables

1. Layout:

   ```text
   compose/<stack>/compose.yaml   seal, vault, data, app
   config/defaults.env            image pins, host ports, names (tracked)
   scripts/                       bash helpers behind make targets
   terraform/                     vault-platform, vault-database (03.01)
   vault/vault-s/config.hcl       Vault server configs
   vault/vault-1/config.hcl
   vault/policies/                Vault policies as files
   vault-tls/                     listener cert + chain (key gitignored)
   .secrets/                      vault/, terraform/, tls/, legacy/ (gitignored)
   docs/STATE.md                  what each prompt did and deferred
   ```

2. `Makefile`. Sections: Podman, Stacks, TLS, Vault, Terraform, App, Tests,
   Maintenance. Targets now: `help`, `check`, `status`, `ps`, `volumes`,
   `network`, `ports-check`, `compose-config`, `gen-certs`, `certs-status`,
   and generated `<stack>-up/-down/-logs`. A stack without a compose file
   reports "not implemented yet" and exits non-zero.
3. `scripts/compose.sh <stack> <args…>`: project `srot-<stack>`,
   `--project-directory compose/<stack>`, env files `config/defaults.env`
   then `.env`, unsets `COMPOSE_FILE`/`COMPOSE_PROFILES`, retries once on the
   dependent-container race.
4. `scripts/podman-check.sh`: client, machine, service, compose provider,
   memory (minimum 4 GiB), VM clock skew (limit 30s).
5. `scripts/network.sh`: create `srot-internal` if absent.
6. `scripts/ports-check.sh`: read every `SROT_PORT_*` from the effective
   config, report each that is already bound and by which container.
7. `scripts/common.sh` (source only): `srot_conf NAME` (`.env` over
   defaults), node addressing for `vault-s` and `vault-1` (host URL from the
   port table), `VAULT_CACERT`, `vault_json` (exit 2 = sealed is fine),
   `vault_wait reachable|unsealed`, `vault_init_field <cluster> <jq>`,
   `vault_root <cluster>`. Clusters: `seal`, `vault`.
8. `scripts/gen-certs.sh` behind `make gen-certs` and `make certs-status`:
   - a lab root CA (EC P-384, 5 years) in `.secrets/tls/ca.{key,crt}`,
     created once and never silently replaced
   - one listener certificate (EC P-256, 825 days) with SANs `vault-s`,
     `vault-1`, `srot-vault-s`, `srot-vault-1`, `localhost`, `127.0.0.1`
   - writes `vault-tls/vault.crt`, `vault-tls/vault.key` (0600, gitignored),
     `vault-tls/ca-chain.pem`
   - idempotent; `--reissue` re-signs the leaf and SIGHUPs running nodes;
     archives the old files to `.secrets/legacy/<date>/vault-tls-<time>/`
9. `scripts/vault-server.sh` (POSIX sh, runs in the Vault image): read the
   Transit token from `/run/secrets/transit-token` when that file is present
   and non-empty, `mkdir -p` data and audit dirs, touch the audit file,
   `exec vault server -config=/vault/config/config.hcl`.
10. `.env.example`: `VAULT_IMAGE` override, `VAULT_LICENSE` (only for an
    Enterprise image), `POSTGRES_SUPERUSER_PASSWORD`. Every password has a
    `make env-init` that fills empty values with `openssl rand -hex 24` in
    `.env` without overwriting existing ones.
11. `.gitignore`: add `.secrets/**` except `.gitkeep`, `vault-tls/vault.key`,
    `terraform/**/.terraform/`. Remove the Python and IDE noise that does not
    apply to this repo only if it is obviously irrelevant; keep the rest.
    `.containerignore` in `app/api` and `app/web` with `._*`, `.DS_Store`,
    `node_modules`, `.env*`, `dist`.
12. Legacy: move `app/api/.env` (holds a live-looking `VAULT_TOKEN`) and the
    root `.env` if non-empty to `.secrets/legacy/<date>/`, preserving
    relative paths. Remove `compose.yml` (git history keeps it). Do not read
    or touch `../shared/`.
13. `compose/README.md`: one paragraph per stack and the persistence table
    from the brief.
14. `docs/STATE.md` started.

## Design rules

- The Makefile is the only entry point. Every documented workflow is a
  `make` target with a `##` help string; targets that change state say
  "(changes state)".
- Read-only targets are safe at any time.
- Nothing in this prompt starts a container.

## Validation

```bash
make help
make check
make env-init && grep -c '^POSTGRES_SUPERUSER_PASSWORD=.\+' .env   # 1
make ports-check
make network && podman network exists srot-internal
make gen-certs && make gen-certs          # second run changes nothing
openssl verify -CAfile vault-tls/ca-chain.pem vault-tls/vault.crt
openssl x509 -in vault-tls/vault.crt -noout -ext subjectAltName | grep -c srot-vault-1
make compose-config                       # "No compose.yaml files exist yet." is acceptable
grep -rIl docker Makefile scripts/        # no output
git status --short .secrets               # nothing except .gitkeep files
test ! -e app/api/.env && test ! -e compose.yml
```
