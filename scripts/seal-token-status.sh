#!/usr/bin/env bash
# scripts/seal-token-status.sh — is the Transit seal token the RUNNING vault-1
# process holds still accepted by vault-s, and where did it come from? A
# vault-1 whose token was revoked keeps running but cannot restart unsealed,
# so this is the check that catches it before the next restart. Read-only.
set -uo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
set +e

[ "$(srot_container_state srot-vault-1)" = running ] || { echo "vault-1: not running"; exit 1; }

# PID 1 is the vault server; its environment holds the token it started with.
held_src='tr "\0" "\n" </proc/1/environ | sed -n "s/^VAULT_TOKEN=//p"'
# Compare hashes (never print a token); strip newlines, which differ between
# the environment and the files.
h() { tr -d '\r\n' | shasum -a 256 | cut -c1-16; }
held_hash=$(podman exec srot-vault-1 sh -c "$held_src" | h)
sink_hash=$(podman exec srot-vault-1 cat /run/secrets/seal/transit-token 2>/dev/null | h)
boot_hash=$(h <"$SROT_STATE/transit-token" 2>/dev/null)
empty_hash=$(printf '' | h)

source=unknown
if [ "$held_hash" = "$sink_hash" ] && [ "$sink_hash" != "$empty_hash" ]; then
  source="seal agent sink"
elif [ "$held_hash" = "$boot_hash" ]; then
  source="bootstrap fallback"
elif [ "$sink_hash" != "$empty_hash" ]; then
  source="an earlier seal agent token (replaced in the sink since vault-1 started)"
fi

if podman exec srot-vault-1 sh -c "VAULT_TOKEN=\$($held_src) VAULT_ADDR=https://vault-s:8200 VAULT_CACERT=/vault/config/tls/ca-chain.pem vault token lookup >/dev/null 2>&1"; then
  echo "vault-1: seal token valid (source: $source)"
  [ "$source" = "bootstrap fallback" ] && echo "         vault-1 runs on the bootstrap token; make vault-recreate moves it to the seal agent's"
  exit 0
fi
echo "vault-1: seal token REJECTED by vault-s (source: $source)."
echo "         vault-1 keeps running but would not unseal after a restart. Fix: make vault-recreate (it starts on the seal agent's fresh token)."
exit 1
