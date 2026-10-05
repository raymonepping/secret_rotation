# Compose stacks

One Compose project per stack, named `srot-<stack>`, all on the external
network `srot-internal`. Run them through `make` (or
`scripts/compose.sh <stack> …`), never with a bare `podman compose`: the
wrapper sets the project name, project directory and both env files.

| Stack | Contains | Needs first |
| --- | --- | --- |
| `seal` | `srot-vault-s`: single-node Raft, Shamir 1-of-1. Holds the Transit key `autounseal`. Never unseals itself; `make unseal` does. `srot-seal-rotator` and `srot-seal-agent` keep vault-1's Transit seal token fresh in the `seal-token` volume. | network, TLS; the seal rotator needs `make tf-seal` and `make rotator-bootstrap` |
| `vault` | `srot-vault-1`: the application Vault. Auto-unseals through vault-s's Transit key. All database configuration lives here (Terraform). | vault-s unsealed |
| `data` | `srot-postgres`: PostgreSQL 16, database `hospital`, users `vault_mgmt` and `surgeon_svc`. | network |
| `app` | `srot-rotator` (keeps the API's AppRole secret-id valid), `srot-vault-agent` (AppRole → token file), `srot-api` (Express), `srot-web` (nginx serving the React build, proxying `/api`). | vault-1 configured by Terraform, postgres, `make rotator-bootstrap` |

## Persistence

| Service | Volume / mount | Class | In `make backup` |
| --- | --- | --- | --- |
| vault-s | `srot-seal_vault-s-data` | persistent | yes (Raft snapshot: it holds the Transit key, without which vault-1's data cannot be unsealed) |
| vault-s | `srot-seal_vault-s-audit` | persistent | no |
| vault-1 | `srot-vault_vault-1-data` | persistent | yes (Raft snapshot) |
| vault-1 | `srot-vault_vault-1-audit` | persistent | no |
| postgres | `srot-data_postgres-data` | persistent | yes (`pg_dump`) |
| both Vault nodes | `vault/*/config.hcl`, `vault-tls/` | host | tracked / regenerated |
| vault-1 | `.secrets/vault/transit-token` (bootstrap fallback seal token) | host | yes |
| seal-agent, vault-1 | `srot-seal_seal-token` (the Transit seal token vault-1 starts with) | ephemeral content | no |
| seal-rotator | `.secrets/vault/seal-rotator/` (its own AppRole) | host | yes |
| seal-rotator, seal-agent | `srot-seal_approle-seal` (seal-autounseal role-id, secret-id) | persistent | no (re-issued on an empty volume) |
| rotator | `.secrets/vault/rotator/` (its own AppRole) | host | yes |
| rotator, vault-agent | `srot-app_approle-api` (API role-id, secret-id, metadata) | persistent | no (the rotator re-issues on an empty volume) |
| vault-agent, api | `srot-app_agent-token` (token sink) | ephemeral | no |
| api, web | none | ephemeral | no |

Persistent volumes carry the label `io.srot.data=true`. `make *-down` and
`make down` never remove volumes; only `make clean-slate` does, after a
typed confirmation.
