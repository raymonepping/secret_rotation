#!/usr/bin/env bash
# scripts/agents-recover.sh — the one manual repair, for what the machines
# cannot heal themselves: a rotator whose own credential is gone. Re-delivers
# it, gives each rotator a fresh pass, and restarts any agent whose token
# Vault rejects. Safe to run any time. A vault-1 holding a revoked seal token
# is reported (make vault-recreate), never restarted from here.
set -uo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# plane | rotator container | agent container
for row in "seal srot-seal-rotator srot-seal-agent" "app srot-rotator srot-vault-agent"; do
  read -r plane rot agent <<<"$row"
  if podman container exists "$rot"; then
    if ! podman exec "$rot" sh -c 't=$(vault write -field=token auth/approle/login role_id="$(cat /run/rotator/role-id)" secret_id="$(cat /run/rotator/secret-id)" 2>/dev/null) && VAULT_TOKEN=$t vault token revoke -self >/dev/null 2>&1'; then
      echo "agents-recover: $rot cannot log in — re-issuing its credential"
      "$root/scripts/rotator-bootstrap.sh" "$plane"
    fi
    # A restart is a fresh pass now rather than at the next interval.
    podman restart "$rot" >/dev/null && echo "agents-recover: $rot restarted (fresh pass)"
  fi
  if podman container exists "$agent" &&
    ! podman exec "$agent" sh -c 'VAULT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null) vault token lookup >/dev/null 2>&1'; then
    echo "agents-recover: restarting $agent"
    podman restart "$agent" >/dev/null 2>&1 || podman start "$agent" >/dev/null
  fi
done
sleep 8
"$root/scripts/agents-status.sh"
