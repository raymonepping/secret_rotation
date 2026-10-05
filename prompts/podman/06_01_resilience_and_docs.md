# Prompt podman/06.01 — Resilience and docs

Read `prompts/podman/00_01_brief.md` first. Requires 05.01.

## Why this prompt exists

The stack now builds itself, but the README still describes three terminals
and `docker-compose`. The one destructive operation (starting over) has no
safe path, and nothing has been tested from a truly empty machine state.

## Goal

A new reader can go from clone to running demo with `make env-init`,
`make gen-certs`, `make bootstrap`, and back to zero with
`make clean-slate`, and every step is documented.

## Deliverables

1. `make bootstrap`: the first-run path in order (check, network,
   gen-certs, vault-bootstrap, data-up, tf-all, app-credentials, app-up,
   verify). Idempotent.
2. `make doctor`: read-only diagnosis: VM clock skew, containers by stack,
   seal state, init files versus storage (the four cases), Terraform state
   present, agent token valid, ports. Each problem with the make target
   that fixes it.
3. `make backup`: Raft snapshot of vault-1 (root token, via the CLI),
   `pg_dump` of `hospital`, and a tarball of `.secrets/vault` and
   `.secrets/terraform` into `backups/<timestamp>/` (gitignored, 0600). Say in
   the docs that the snapshot is useless without the matching init files and
   vault-s data.
4. `make clean-slate`: typed confirmation (`DELETE`), stops every `srot-`
   container, removes `srot-` containers and the volumes labelled
   `io.srot.data=true`, moves `.secrets/vault/*.json`, the Transit token,
   AppRole credentials and Terraform state to `.secrets/legacy/<date>/`. TLS
   material is kept. Then `make bootstrap` must work.
5. `README.md` rewritten: what the demo shows (the three lanes in one
   paragraph each, with the Vault path), architecture diagram (text),
   quick start, daily use (`make up/down/unseal`), make target table,
   configuration, troubleshooting (from the gotchas), and links to
   `DESIGN.md` and `compose/README.md`. Screenshot at the top.
6. `CHANGELOG.md`: an `[Unreleased]` entry listing what this migration
   changed, under Added / Changed / Removed / Security.
7. `CLAUDE.md`: short operating rules for agents (operate through make, no
   tokens in tracked files, filter by `srot-`, never prune, scripts are bash,
   commit only when asked).
8. `FOLDER_TREE.md` regenerated or removed (it is gitignored and stale).
9. `docs/STATE.md` final: done, deferred, known limits.

## Validation

```bash
make doctor
make backup && ls backups/*/
make clean-slate                 # type DELETE
make bootstrap                   # from zero to verified
make down && make up && make verify
git status --short               # no secrets, no state, no node_modules
gitleaks detect --no-banner --redact 2>/dev/null || true   # no findings
```
