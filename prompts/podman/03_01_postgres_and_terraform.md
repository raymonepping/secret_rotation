# Prompt podman/03.01 — PostgreSQL and Terraform

Read `prompts/podman/00_01_brief.md` first. Requires 02.01.

## Why this prompt exists

Everything the three lanes depend on (the database mount, the connection,
the dynamic and static roles) was created by hand and is written down
nowhere. The connection used the PostgreSQL superuser, so "rotate root" in
the Doctor lane rotated the password of the account the container itself
was created with. Terraform makes the configuration declared, reviewable and
repeatable; a dedicated management user makes root rotation safe to press
as often as the demo likes.

## Goal

`make tf-all` takes a freshly bootstrapped vault-1 and an empty PostgreSQL
to the full configuration the lanes need, and a second `make tf-plan-all`
reports no changes.

## Reference

- `vault_reference/terraform/vault-database/` (management role,
  `ignore_changes = [postgresql[0].password]`, creation and revocation
  statements)
- `vault_reference/scripts/tf.sh` (env export, state outside the tree,
  password reset when the connection has to be created again)
- `vault_reference/Makefile` targets `tf-*`, `db-rotate-root`, `db-test`
- This repo: `postgres/init/01-demo.sql`, `app/api/src/routes/*.js`

## Deliverables

1. `compose/data/compose.yaml`: `srot-postgres` from
   `docker.io/library/postgres:16.14-alpine`, named volume `postgres-data`
   (persistent), init directory mounted read-only, port
   `127.0.0.1:${SROT_PORT_POSTGRES}:5432`, superuser password from `.env`,
   healthcheck `pg_isready` (with `$$`).
2. `postgres/init/`:
   - `01-schema.sql`: database `hospital`, table `patient_status_demo` with
     the existing seed rows. `REVOKE CONNECT ... FROM PUBLIC`.
   - `02-roles.sh`: creates `vault_mgmt` (LOGIN, CREATEROLE, CONNECT on
     `hospital`, SELECT on the table WITH GRANT OPTION, permission to ALTER
     `surgeon_svc`) and `surgeon_svc` (LOGIN, SELECT on the table). Their
     initial passwords come from the environment (`VAULT_MGMT_PASSWORD`,
     `SURGEON_SVC_PASSWORD`), which `make data-up` generates once into
     `.secrets/postgres.env` (0600). No password in a tracked file.
3. `terraform/vault-platform/` (state `.secrets/terraform/vault-platform.tfstate`):
   file audit device if not managed by bootstrap (choose one owner and say
   which), `auth/approle`, policies from `vault/policies/*.hcl` via `file()`:
   - `secret-theatre-api.hcl`: read `database/creds/patient-readonly`,
     read `database/static-creds/surgeon`, update
     `database/rotate-role/surgeon`, update
     `database/rotate-root/hospital-postgres`, update `sys/leases/revoke`,
     read `database/static-roles/surgeon`. Nothing else.
   - AppRole role `secret-theatre-api` with `token_policies` (full list),
     `token_ttl=15m`, `token_max_ttl=1h`, `secret_id_ttl=0` (lab; say so),
     `token_bound_cidrs` and `secret_id_bound_cidrs` restricted to the
     `srot-internal` subnet, read at apply time from Podman.
   - output: role-id (not sensitive), no secret-id in state.
4. `terraform/vault-database/` (state in `.secrets/terraform/`):
   mount `database`, connection `hospital-postgres` as `vault_mgmt`
   (`sslmode=disable` on the internal network, commented), allowed roles
   both; dynamic role `patient-readonly` (creation: role with VALID UNTIL,
   CONNECT on `hospital`, SELECT on the table; revocation: revoke and drop;
   TTL 60s, max 120s); static role `surgeon` for `surgeon_svc`, rotation
   period 120s. `ignore_changes` on the connection password.
5. `scripts/tf.sh <root> <plan|apply|destroy|output>`: exports
   `VAULT_ADDR` (vault-1's loopback port), `VAULT_CACERT`, the root token
   from `.secrets/vault/vault-init.json` (lab shortcut, comment says so),
   `TF_VAR_*` from `.secrets/postgres.env` and the network subnet. `init
   -input=false` then the action; `plan` uses `-detailed-exitcode`. Before
   an apply that must create the connection (not in state), reset
   `vault_mgmt`'s password through the superuser and hand the new value to
   Terraform, because after a root rotation only Vault knows the old one.
6. Make targets: `data-up`, `data-down`, `data-logs`, `psql` (superuser shell
   in the container), `tf-platform`, `tf-database`, `tf-all` (data-up, both
   roots in order), `tf-plan-all`, `tf-destroy` (typed confirmation),
   `db-rotate-root` (rotate `vault_mgmt` once; prints that only Vault knows
   it now), `db-test` (issue a dynamic credential with the CLI, connect with
   it via `psql` in the container, revoke it, prove the role is gone).
7. `make verify`, section "database": mount and connection exist, both roles
   exist, a dynamic credential connects and can SELECT, and after revoke it
   cannot connect; static credential connects; `vault_mgmt` cannot log in
   with the initial password from `.secrets/postgres.env` after
   `db-rotate-root` was run (skip with a note if it was not).
8. `docs/STATE.md` updated.

## Design rules

- Terraform state holds secrets. It lives in `.secrets/terraform/`, mode
  0600, never next to the code.
- Policies are files. Token roles list their full policy set.
- Nothing in a `.tf` file is a literal secret.
- Root rotation is one-way for the initial password. That is the point of
  the Doctor lane; the docs say so.

## Validation

```bash
make data-up
make tf-all
make tf-plan-all                         # both roots: No changes.
make db-test
make db-rotate-root
make tf-plan-all                         # still No changes (password ignored)
make verify
make data-down && make data-up && make db-test     # data survived
ls terraform/*/terraform.tfstate* 2>/dev/null       # no output
```
