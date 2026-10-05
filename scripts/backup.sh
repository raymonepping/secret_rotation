#!/usr/bin/env bash
# scripts/backup.sh — everything needed to bring this lab back:
#
#   vault-s.snap      Raft snapshot of vault-s (holds the Transit key)
#   vault-1.snap      Raft snapshot of vault-1 (database config, leases)
#   hospital.sql      pg_dump of the hospital database (roles are in globals.sql)
#   globals.sql       pg_dumpall --globals-only (vault_mgmt, surgeon_svc, …)
#   secrets.tar       .secrets/{vault,terraform,tls,postgres.env}
#
# A snapshot is useless without the matching init files (unseal key, root
# token) and vault-1's snapshot is useless without vault-s's Transit key:
# keep all of it together. Written to backups/<UTC timestamp>/, mode 0600.
set -euo pipefail
umask 077
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
cd "$SROT_ROOT"

dest="backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$dest"
chmod 700 backups "$dest"

for node in vault-s vault-1; do
  vault_node "$node"
  vault_root "$(vault_cluster_of "$node")"
  vault operator raft snapshot save "$dest/$node.snap"
  echo "backup: $node snapshot saved"
done
unset VAULT_TOKEN

db=$(srot_conf SROT_DB_NAME)
podman exec srot-postgres pg_dump -U postgres -d "$db" >"$dest/$db.sql"
podman exec srot-postgres pg_dumpall -U postgres --globals-only >"$dest/globals.sql"
echo "backup: $db dumped"

tar -cf "$dest/secrets.tar" -C .secrets vault terraform tls postgres.env 2>/dev/null ||
  tar -cf "$dest/secrets.tar" -C .secrets vault terraform tls
chmod 600 "$dest"/*
echo "backup: written to $dest/ ($(du -sh "$dest" | cut -f1))"
