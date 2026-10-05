#!/usr/bin/env bash
# scripts/seal-up.sh — start the seal plane in the only order that works:
#
#   1. vault-s alone        it comes up sealed; nothing else can proceed
#   2. unseal               with the key in .secrets/vault/seal-init.json
#   3. rotator + agent      they need an unsealed vault-s; `compose up` would
#                           otherwise block on their health behind a sealed node
#   4. wait for the agent   so vault-1, started next, finds a fresh seal token
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
compose() { "$SROT_ROOT/scripts/compose.sh" seal "$@"; }

"$SROT_ROOT/scripts/network.sh"
ensure_seal_token_volume
compose up -d vault-s
"$SROT_ROOT/scripts/vault-unseal.sh"
vault_node vault-s
vault_wait active

# Keep the bootstrap fallback token alive: it is periodic, and nothing else
# renews it while vault-1 runs on the agent's token.
if [ -s "$SROT_STATE/transit-token" ]; then
  VAULT_TOKEN=$(cat "$SROT_STATE/transit-token") vault token renew >/dev/null 2>&1 ||
    echo "seal-up: note — the bootstrap fallback seal token is no longer valid (make vault-bootstrap re-issues it)"
fi

if [ -s "$SROT_STATE/seal-rotator/secret-id" ]; then
  compose up -d
  n=0
  until [ "$(podman container inspect srot-seal-agent --format '{{.State.Health.Status}}' 2>/dev/null)" = healthy ]; do
    n=$((n + 1))
    if [ "$n" -ge 60 ]; then
      echo "seal-up: WARNING the seal agent is not healthy after 120s; vault-1 will fall back to the bootstrap token (make agents-recover)" >&2
      exit 0
    fi
    sleep 2
  done
  echo "seal-up: seal agent healthy — fresh seal token in the sink"
else
  echo "seal-up: seal plane identity not set up yet (make tf-seal && make rotator-bootstrap)"
fi
