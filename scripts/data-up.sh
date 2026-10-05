#!/usr/bin/env bash
# scripts/data-up.sh — generate the initial PostgreSQL role passwords once,
# then start the data stack and wait until it accepts connections.
set -euo pipefail
umask 077
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"

pg_env="$SROT_ROOT/.secrets/postgres.env"
if [ ! -s "$pg_env" ]; then
  {
    echo "# Initial passwords; read once by postgres/init/02-roles.sh on an empty volume."
    echo "# After make db-rotate-root only Vault knows vault_mgmt's password, and Vault"
    echo "# rotates surgeon_svc's password itself."
    echo "VAULT_MGMT_PASSWORD=$(openssl rand -hex 24)"
    echo "SURGEON_SVC_PASSWORD=$(openssl rand -hex 24)"
  } >"$pg_env"
  echo "data-up: generated .secrets/postgres.env"
fi

"$SROT_ROOT/scripts/network.sh"
"$SROT_ROOT/scripts/compose.sh" data up -d
for _ in $(seq 1 40); do
  if podman exec srot-postgres pg_isready -q -U postgres -d "$(srot_conf SROT_DB_NAME)" 2>/dev/null; then
    echo "data-up: postgres is ready"
    exit 0
  fi
  sleep 2
done
echo "data-up: postgres did not become ready; see make data-logs" >&2
exit 1
