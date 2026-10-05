#!/usr/bin/env bash
# scripts/db-rotate-root.sh — rotate the connection's own credential
# (vault_mgmt). Afterwards only Vault knows that password: the value in
# .secrets/postgres.env is dead. This is what the Doctor lane does; it is
# safe to repeat because vault_mgmt is not the PostgreSQL superuser.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
vault_node vault-1
vault_root vault
conn=$(srot_conf SROT_DB_CONNECTION)
vault write -f "database/rotate-root/$conn" >/dev/null
echo "db-rotate-root: $conn rotated — only Vault knows $(srot_conf SROT_DB_MGMT_USER)'s password now"
