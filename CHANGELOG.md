# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Podman + Make + Terraform stack modelled on `vault_reference`: Compose
  stacks `seal`, `vault`, `data`, `app`; `make bootstrap` from zero to
  verified; `make up`/`down` cold start with the vault-s unseal.
- vault-s (Shamir, Transit key `autounseal`) and vault-1 (Transit
  auto-unseal), TLS 1.3 with a lab CA; idempotent bootstrap that compares init
  files with storage.
- Terraform roots `vault-platform` (AppRole, API policy) and `vault-database`
  (mount, connection, dynamic role `patient-readonly`, static role `surgeon`).
- Vault Agent (AppRole, token watchdog) supplying the API's token as a file.
- Containerised API and UI (nginx, same origin, CSP); `GET /api/platform`.
- `make verify` (45 end-to-end checks), `doctor`, `backup`, `clean-slate`,
  `clock-sync`, `db-test`, `db-rotate-root`.
- `DESIGN.md`: the Daylight Glass design system, applied to the UI.
- Secret-id rotator sidecar (Project Durin's pattern): the API identity's
  90-day secret-id is issued, rotated and replaced by `srot-rotator` on
  Vault's own answer; `make rotator-bootstrap`, `agents-status`,
  `agents-recover`, `rotate-now`, `rotation-test` (five self-healing cases).
- Seal plane identity: `terraform/vault-seal`, `srot-seal-rotator` and
  `srot-seal-agent` keep vault-1's Transit seal token fresh; `vault-server.sh`
  prefers it (verified against vault-s) over the bootstrap fallback;
  `make tf-seal`, `seal-token-status`; `doctor` flags a revoked seal token and
  containers whose bind-mount sources have moved.

### Changed

- UI redesigned on Daylight Glass: rail, top bar with live seal state,
  status pills, TTL bars, Vault's verbatim errors. Lane behaviour unchanged.
- Countdowns run from the lease duration on the browser's clock, so VM clock
  skew no longer shows as an expired lease.
- Database `librarydemo` → `hospital`; Vault connects as `vault_mgmt`
  (CREATEROLE, not a superuser). Names come from `config/defaults.env`.

### Removed

- `compose.yml` and its hardcoded password and `../shared` bind mount.
- `dotenv` from the API; the old dark theme and Vite sample assets.

### Security

- No long-lived `VAULT_TOKEN` anywhere; the old `app/api/.env` was moved to
  `.secrets/legacy/`. AppRole bound to the Podman network's CIDR.
- The API's secret-id expires (90 days, `auth/approle` tuned so the mount
  does not silently cap it at 24h); the hand-issued non-expiring one was
  destroyed. The rotator's policy can manage that role's secret-ids only.
- Containers run non-root with `cap_drop: ALL`, `no-new-privileges`,
  read-only roots where possible.
