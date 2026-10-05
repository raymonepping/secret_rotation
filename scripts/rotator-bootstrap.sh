#!/usr/bin/env bash
# scripts/rotator-bootstrap.sh [seal|app …] — deliver each plane's rotator
# credential (default: both), mode 0600:
#
#   seal  .secrets/vault/seal-rotator/  role seal-rotator on vault-s
#   app   .secrets/vault/rotator/       role secret-theatre-rotator on vault-1
#
# These are the only machine credentials a human (or this script, with the
# lab root token) hands over. Everything else — the API's and the seal
# agent's role-ids, their expiring secret-ids, their tokens — is issued and
# rotated by machines. Idempotent: keeps a secret-id Vault still accepts.
set -euo pipefail
umask 077
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"

# deliver <node> <cluster> <role> <dir>
deliver() {
  local role=$3 dir=$4 out
  vault_node "$1"
  vault_root "$2"
  mkdir -p "$dir"
  chmod 700 "$dir"
  # Write in place: the directory is bind-mounted into the rotator.
  vault read -field=role_id "auth/approle/role/$role/role-id" >"$dir/role-id.tmp"
  cat "$dir/role-id.tmp" >"$dir/role-id"
  rm -f "$dir/role-id.tmp"
  if [ -s "$dir/secret-id" ] &&
    out=$(vault write -format=json "auth/approle/role/$role/secret-id/lookup" secret_id="$(cat "$dir/secret-id")" 2>/dev/null) &&
    jq -e '.data.secret_id_accessor' <<<"$out" >/dev/null 2>&1; then
    echo "rotator-bootstrap: $role secret-id is still valid — kept"
  else
    vault write -field=secret_id -f "auth/approle/role/$role/secret-id" metadata=consumer="$role" >"$dir/secret-id.tmp"
    cat "$dir/secret-id.tmp" >"$dir/secret-id"
    rm -f "$dir/secret-id.tmp"
    echo "rotator-bootstrap: $role secret-id issued (${dir#"$SROT_ROOT"/})"
  fi
  unset VAULT_TOKEN
}

planes=${*:-seal app}
for plane in $planes; do
  case "$plane" in
  seal) deliver vault-s seal seal-rotator "$SROT_STATE/seal-rotator" ;;
  app) deliver vault-1 vault secret-theatre-rotator "$SROT_STATE/rotator" ;;
  *) echo "rotator-bootstrap: unknown plane '$plane' (seal|app)" >&2; exit 64 ;;
  esac
done

vault_node vault-1
vault_root vault

# Migration from 04.01: the API's secret-id used to be issued by hand, with no
# expiry, into .secrets/vault/approle-api/. Destroy it in Vault (it would stay
# valid forever) and keep the files as evidence.
legacy_dir="$SROT_STATE/approle-api"
if [ -d "$legacy_dir" ]; then
  if [ -s "$legacy_dir/secret-id" ]; then
    acc=$(vault write -field=secret_id_accessor auth/approle/role/secret-theatre-api/secret-id/lookup \
      secret_id="$(cat "$legacy_dir/secret-id")" 2>/dev/null || true)
    if [ -n "$acc" ]; then
      vault write auth/approle/role/secret-theatre-api/secret-id-accessor/destroy secret_id_accessor="$acc" >/dev/null
      echo "rotator-bootstrap: destroyed the hand-issued, non-expiring API secret-id"
    fi
  fi
  dest="$SROT_ROOT/.secrets/legacy/$(date +%Y-%m-%d)/approle-api-$(date +%H%M%S)"
  mkdir -p "$(dirname "$dest")"
  mv "$legacy_dir" "$dest"
  echo "rotator-bootstrap: moved .secrets/vault/approle-api to ${dest#"$SROT_ROOT"/.secrets/}"
fi

# A running rotator reads its credentials at every pass; nothing to restart.
