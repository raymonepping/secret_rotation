# Prompt podman/00.01 — Brief (read first, every session)

This file is the shared context for moving `secret_rotation` onto the
Podman + Make + Terraform pattern of `vault_reference`, and onto its design
system. It is not a task by itself. Run the prompts in number order, one per
session, and do not start a prompt until the previous prompt's Validation
block passes.

## Your role

You are a Podman specialist with working knowledge of Vault (Raft, Transit
auto-unseal, the database secrets engine, AppRole, Vault Agent), Terraform
(the `hashicorp/vault` provider), PostgreSQL role design, and React. You are
turning a demo that only runs against a hand-configured Vault into a stack
that builds itself from zero with `make`.

The reference implementation is
`/Users/raymon.epping/Documents/VSC/Personal/vault_reference`. Read it instead
of inventing a pattern. It is much larger (ten Vault nodes, replication,
portal, SIEM); take its *shape*, not its size:

- `Makefile` (sections, `##` help strings, "(changes state)" marking)
- `scripts/compose.sh`, `podman-check.sh`, `network.sh`, `vault-common.sh`
- `scripts/vault-bootstrap.sh`, `vault-unseal.sh`, `vault-server.sh`, `tf.sh`
- `compose/seal/compose.yaml`, `compose/primary/compose.yaml`
- `compose/common/agent/entrypoint.sh` (Vault Agent with token watchdog)
- `terraform/vault-database/` (management role, `ignore_changes` on password)
- `home/DESIGN.md`, `home/assets/portal.css`, `home/assets/shell.js`

## What this repository is

"Vault Secret Theatre": a hospital-themed demo of three Vault secret
lifecycles against PostgreSQL, one lane each.

| Lane | Vault feature | API (`app/api`) | Vault path |
| --- | --- | --- | --- |
| Patient | Dynamic credential with a lease; revoke = flatline | `/api/patient/{issue,test,revoke}` | `database/creds/patient-readonly`, `sys/leases/revoke` |
| Surgeon | Static role; Vault rotates an existing user's password | `/api/surgeon/{issue,test,rotate}` | `database/static-creds/surgeon`, `database/rotate-role/surgeon` |
| Doctor | Root credential rotation; only Vault knows the password afterwards | `/api/doctor/rotate-root` | `database/rotate-root/<connection>` |

`app/api` is Express 5 (ESM), `app/web` is React 19 + Vite 8 with a dark
"ICU monitor" theme. Auto Mode drives all three lanes on timers.

## Current state (verified 2026-10-05)

- Only Postgres has a Compose file (`compose.yml`, container
  `library-postgres`, hardcoded password, bind mount `../shared/postgres/data`
  outside the repo).
- The Vault side is not in the repository at all. The database mount, the
  connection `library-postgres`, the roles `patient-readonly` and `surgeon`
  were configured by hand on a Vault whose data sits in `../shared/vault`.
- `app/api/.env` holds a long-lived `VAULT_TOKEN`. The API is started with
  `npm run dev` on the host; the web app with `npm run dev` on 5173, while
  the API's CORS only allows `:3001`.
- Names are left over from a books project: database `librarydemo`, user
  `vaultadmin`, service name `library-api`.
- Podman 6.1.1, machine `podman-machine-default` (applehv, 12 CPU, 48 GiB).
  `podman compose` is Docker Compose v2 behind Podman. Host tools: `vault`
  2.1 ent, `terraform` 1.14, `jq`, `openssl`, `node` 25.
- vault_reference uses host ports 8190, 8200–8212, 5432, 8080, 8443, 3001;
  a KinD cluster holds 8090. This stack must run beside both.

## Target topology

```text
network srot-internal
 └─ TLS material (.secrets/tls CA → vault-tls/)          every Vault listener is TLS 1.3
     └─ seal:  vault-s ── init (Shamir 1/1) ── unseal ── transit key `autounseal` + policy + token
         └─ vault: vault-1  auto-unseal via vault-s ── init (1 recovery share)
              ├─ data: postgres  (db `hospital`, roles vault_mgmt + surgeon_svc)
              ├─ Terraform vault-platform: audit, AppRole, policies, app identity
              ├─ Terraform vault-database: mount, connection, dynamic + static role
              └─ app: vault-agent (AppRole → token sink) ── api ── web (nginx, /api proxy)
```

## Decisions already made (change here, not in the phase prompts)

| # | Decision | Default |
| --- | --- | --- |
| D1 | Vault edition | Vault Community `docker.io/hashicorp/vault:2.0.0`. Nothing here needs Enterprise, and the demo should not stop working when a licence expires. `VAULT_IMAGE` in `.env` can point at an Enterprise image; then `VAULT_LICENSE` is required. |
| D2 | Cluster size | `vault-s` plus a single Raft node `vault-1`. The demo is about secret lifecycles, not HA. The node keeps its Raft config so a second node can be added later. |
| D3 | Old data | Rebuild from zero. Do not read or modify `../shared/`; it belongs to the old setup and may be used by other projects. |
| D4 | Naming | Prefix `srot-` for containers, volumes, projects, network. Database `hospital`, connection `hospital-postgres`, dynamic role `patient-readonly`, static role `surgeon` (database user `surgeon_svc`), management user `vault_mgmt`. The API reads these names from the environment. |
| D5 | Host ports (loopback only) | vault-s 18190, vault-1 18200, postgres 15432, api 13000, web 13001. Tracked in `config/defaults.env`, overridable in `.env`. |
| D6 | TLS | A lab CA created by `make gen-certs` in `.secrets/tls/`. Vault listeners use a leaf from it; host tooling and the API verify against `vault-tls/ca-chain.pem`. No `-tls-skip-verify`, no `VAULT_SKIP_VERIFY`, no `NODE_TLS_REJECT_UNAUTHORIZED=0`. |
| D7 | App identity | The API never holds a static token. A Vault Agent (AppRole) writes a token to a shared volume; the API reads the file per request. Since 07.01 the secret-id expires (90 days) and a rotator sidecar keeps it valid, as in Project Durin; the only credential handed over is the rotator's own (`make rotator-bootstrap`). |
| D8 | Lease and rotation timing | Dynamic role TTL 60s, max 120s. Static role rotation period 120s. Short on purpose: the UI shows the countdowns. |
| D9 | Design | `vault_reference`'s portal design system, extracted to `DESIGN.md` at the repo root and applied to `app/web` in 05.01. |

## Persistence

| Class | Storage | Services |
| --- | --- | --- |
| Persistent | Named volume, label `io.srot.data=true` | vault-s data + audit, vault-1 data + audit, postgres data |
| Host | Bind mount of a tracked or `.secrets/` path | HCL, TLS material, init JSON, Terraform state, AppRole credentials |
| Ephemeral | tmpfs or no volume | Agent token sink, api, web |

`down` never removes named volumes. Only `make clean-slate` does, after a
typed confirmation. A recreated container comes back with its data.

## Ground rules

- Work on branch `podman-make-terraform`. Commit only when asked.
  `commit_gh` stages everything.
- Never print a token, unseal key, recovery key or password. Redact.
- Stale credential files are evidence: move them to
  `.secrets/legacy/<date>/`, do not delete them.
- Filter every `podman` command by the `srot-` prefix. Do not touch
  `vref-*`, `demo-*` (KinD) or any other project's containers.
- Scripts are bash (`#!/usr/bin/env bash`, `set -euo pipefail`) unless they
  run inside a container image without bash. Do not pipe into `grep -q`
  under `pipefail`; capture output first.
- macOS ships GNU Make 3.81. Use nothing newer.
- When a step fails, find the cause in the logs before changing timeouts.
- Record what you did and what you deferred in `docs/STATE.md` at the end of
  each prompt.

## Gotchas carried over from vault_reference

1. `vault status` exits 2 when sealed. That is an answer, not an error.
2. Named volumes are created root-owned; the Vault image's `VOLUME`
   declarations copy up ownership only for its own paths. Create audit files
   in the entrypoint wrapper.
3. The Transit seal token is read once at process start. Replacing it means
   recreating the node that reads it.
4. Bind-mounting a single file and replacing it with `mv` leaves the
   container on the old inode. Write in place.
5. In Compose `CMD-SHELL` healthchecks, `$` must be written `$$`.
6. macOS provenance xattrs break Podman builds of JS projects (`._*` files in
   the context). Every build context has a `.containerignore` with `._*` and
   `.DS_Store`; builds run with `COPYFILE_DISABLE=1`.
7. The Podman VM clock can drift; tokens and leases then fail strangely.
   `make check` reports skew.

## Prompt order

| Prompt | Delivers |
| --- | --- |
| `01_01` | Foundation: layout, Makefile, wrappers, TLS, `.env`, `.secrets`, legacy moves |
| `02_01` | vault-s and vault-1: bootstrap, unseal, cold start, `make verify` v1 |
| `03_01` | PostgreSQL and Terraform: platform + database roots, root rotation |
| `04_01` | App runtime: Vault Agent, containerized API and web, end-to-end lanes |
| `05_01` | Design system: `DESIGN.md` extracted from vault_reference, applied to the UI |
| `06_01` | Resilience and docs: clean-slate, README, CHANGELOG, final validation |
| `07_01` | Foolproof machine identity: rotator + agent as in Durin, self-healing tests |
| `08_01` | The seal plane heals itself too: seal rotator + agent for vault-1's Transit token |
