#!/usr/bin/env bash
# scripts/doctor.sh — what is wrong, and which make target fixes it. Read-only.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
cd "$SROT_ROOT"

problems=0
good() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fix() { printf '  \033[31m✗\033[0m %s\n      fix: %s\n' "$1" "$2"; problems=$((problems + 1)); }

echo "host"
if [ "$(uname -s)" = Darwin ]; then
  vm=$(podman machine ssh date +%s 2>/dev/null | tr -d '\r' | tail -1 || true)
  if [ -n "$vm" ]; then
    skew=$(($(date +%s) - vm)); skew=${skew#-}
    if [ "$skew" -gt 30 ]; then fix "VM clock is ${skew}s off the host (leases look expired or immortal)" "make clock-sync"; else good "VM clock skew ${skew}s"; fi
  else
    fix "cannot reach the Podman machine" "podman machine start"
  fi
fi
[ -s .env ] && good ".env present" || fix ".env missing" "make env-init"
openssl verify -CAfile vault-tls/ca-chain.pem vault-tls/vault.crt >/dev/null 2>&1 && good "listener certificate verifies" || fix "listener certificate missing or does not verify" "make gen-certs"

echo "containers"
for c in srot-vault-s srot-seal-rotator srot-seal-agent srot-vault-1 srot-postgres srot-rotator srot-vault-agent srot-api srot-web; do
  s=$(srot_container_state "$c")
  case "$c:$s" in
  *:running) good "$c running" ;;
  srot-vault-s:* | srot-vault-1:* | srot-seal-*) fix "$c is $s" "make vault-up" ;;
  srot-postgres:*) fix "$c is $s" "make data-up" ;;
  *) fix "$c is $s" "make app-up" ;;
  esac
done

# A container keeps the bind-mount paths it was created with. When a mounted
# file or directory moves, the container runs on but cannot start again —
# its next restart (a watchdog exit, a reboot) fails with "cannot stat".
for c in $(podman ps -a --filter name=^srot- --format '{{.Names}}'); do
  missing=$(podman inspect "$c" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' 2>/dev/null |
    while read -r src; do [ -z "$src" ] || [ -e "$src" ] || echo "$src"; done)
  [ -z "$missing" ] || fix "$c mounts a path that no longer exists (${missing%%$'\n'*}); it cannot restart" "make up (recreates containers from the current compose files)"
done

echo "vault"
# The four cases of init file versus storage, per node.
for node in vault-s vault-1; do
  cluster=$(vault_cluster_of "$node")
  file="$SROT_STATE/$cluster-init.json"
  [ "$(srot_container_state "$(vault_container "$node")")" = running ] || continue
  vault_node "$node"
  if ! s=$(vault_json 2>/dev/null); then fix "$node does not answer" "make vault-up (and podman logs $(vault_container "$node"))"; continue; fi
  init=$(jq -r .initialized <<<"$s")
  if [ "$init" = true ] && [ ! -s "$file" ]; then
    fix "$node is initialized but .secrets/vault/$cluster-init.json is missing" "restore it from backups/*/secrets.tar"
  elif [ "$init" = false ] && [ -s "$file" ]; then
    fix "$node has saved credentials but no storage (volume lost)" "restore the volume, or make clean-slate"
  elif [ "$init" = false ]; then
    fix "$node is not initialized" "make vault-bootstrap"
  elif jq -e .sealed <<<"$s" >/dev/null; then
    if [ "$node" = vault-s ]; then fix "vault-s is sealed" "make unseal"; else fix "vault-1 is sealed" "make vault-up (vault-s must be unsealed first)"; fi
  else
    good "$node initialized and unsealed"
  fi
done

echo "terraform"
for r in vault-platform vault-database; do
  [ -s ".secrets/terraform/$r.tfstate" ] && good "$r state present" || fix "$r has no state" "make tf-all"
done

echo "app identity"
if [ "$(srot_container_state srot-vault-agent)" = running ]; then
  if podman exec srot-vault-agent sh -c 'VAULT_TOKEN=$(cat /vault/secrets/token) vault token lookup >/dev/null' 2>/dev/null; then
    good "agent token valid"
  else
    fix "agent token missing or rejected (its watchdog restarts it within ~1 minute)" "make agents-recover"
  fi
fi
[ -s "$SROT_STATE/rotator/secret-id" ] && good "rotator credential present" || fix "the rotator has no credential" "make rotator-bootstrap"
[ -s "$SROT_STATE/seal-rotator/secret-id" ] && good "seal rotator credential present" || fix "the seal rotator has no credential" "make tf-seal && make rotator-bootstrap && make seal-up"
if [ "$(srot_container_state srot-seal-rotator)" = running ] &&
  ! podman exec srot-seal-rotator sh -c 't=$(vault write -field=token auth/approle/login role_id="$(cat /run/rotator/role-id)" secret_id="$(cat /run/rotator/secret-id)" 2>/dev/null) && VAULT_TOKEN=$t vault token revoke -self >/dev/null 2>&1' 2>/dev/null; then
  fix "the seal rotator's own credential is rejected" "make agents-recover"
fi
if [ "$(srot_container_state srot-vault-1)" = running ]; then
  st=$("$SROT_ROOT/scripts/seal-token-status.sh" 2>/dev/null) && sc=0 || sc=$?
  if [ "$sc" -ne 0 ]; then
    fix "vault-1's seal token REJECTED by vault-s: it runs, but would not unseal after a restart" "make vault-recreate"
  elif grep -q "bootstrap fallback" <<<"$st"; then
    fix "vault-1 runs on the bootstrap fallback seal token, not the seal agent's" "make seal-up && make vault-recreate"
  else
    good "vault-1's seal token is valid and comes from the seal agent"
  fi
fi
if [ "$(srot_container_state srot-rotator)" = running ]; then
  if podman exec srot-rotator sh -c 't=$(vault write -field=token auth/approle/login role_id="$(cat /run/rotator/role-id)" secret_id="$(cat /run/rotator/secret-id)" 2>/dev/null) && VAULT_TOKEN=$t vault token revoke -self >/dev/null 2>&1' 2>/dev/null; then
    good "rotator can log in"
  else
    fix "the rotator's own credential is rejected (it cannot rotate anything)" "make agents-recover"
  fi
fi
[ -d "$SROT_STATE/approle-api" ] && fix "a hand-issued API secret-id from before the rotator still exists" "make rotator-bootstrap (destroys it)"

echo "ports"
if "$SROT_ROOT/scripts/ports-check.sh" >/dev/null 2>&1; then good "no port conflicts"; else fix "a port this stack needs is taken" "make ports-check, then override it in .env"; fi

echo
if [ "$problems" -eq 0 ]; then echo "doctor: nothing wrong found"; else echo "doctor: $problems problem(s)"; exit 1; fi
