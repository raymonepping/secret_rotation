#!/usr/bin/env bash
# scripts/test-rotation.sh — prove both machine identities (the API's and the
# seal plane's) heal credential failures without a human, or with exactly the
# one make target that the doctor names. Changes state: it revokes and destroys
# credentials on purpose. Every case ends with the API issuing a dynamic
# PostgreSQL credential again, through the UI's own endpoint.
set -uo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
set +e
cd "$SROT_ROOT"
pass=0 fail=0
ok() { printf '  \033[32mok\033[0m    %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail + 1)); }
# wait_for <seconds> <description> <command…>: poll every 5s until it succeeds.
wait_for() {
  local max=$1 d=$2 t=0
  shift 2
  until "$@" >/dev/null 2>&1; do
    t=$((t + 5))
    [ "$t" -ge "$max" ] && { bad "$d (not within ${max}s)"; return 1; }
    sleep 5
  done
  ok "$d (${t}s)"
}

ROLE=secret-theatre-api
META=/run/approle/$ROLE/metadata.json
web="http://127.0.0.1:$(srot_conf SROT_PORT_WEB)"
agent_token_ok() { podman exec srot-vault-agent sh -c 'VAULT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null) vault token lookup >/dev/null 2>&1'; }
agent_accessor() { podman exec srot-vault-agent sh -c 'VAULT_TOKEN=$(cat "$TOKEN_FILE") vault token lookup -format=json' | jq -r .data.accessor; }
secret_accessor() { podman exec srot-rotator cat "$META" | jq -r .secret_id_accessor; }
restarts() { podman inspect srot-vault-agent --format '{{.RestartCount}}'; }
# The API works = it can issue (and we revoke) a dynamic credential.
api_works() {
  local c
  c=$(curl -sf -X POST "$web/api/patient/issue") || return 1
  jq -e .ok <<<"$c" >/dev/null || return 1
  curl -sf -X POST -H 'Content-Type: application/json' --data "$(jq -c '{lease_id}' <<<"$c")" "$web/api/patient/revoke" >/dev/null
}
accessor_dead() { ! vault write auth/approle/role/$ROLE/secret-id-accessor/lookup secret_id_accessor="$1" >/dev/null 2>&1; }

vault_node vault-1
vault_root vault
api_works && ok "baseline: the API issues credentials" || bad "baseline: the API issues credentials"

echo
echo "1. The agent's token is revoked"
acc=$(agent_accessor)
r0=$(restarts)
vault token revoke -accessor "$acc" >/dev/null
api_works && bad "the API fails while its token is dead" || ok "the API fails while its token is dead"
wait_for 180 "watchdog restarts the agent and it logs in again" agent_token_ok
[ "$(agent_accessor)" != "$acc" ] && ok "the agent holds a new token" || bad "the agent holds a new token"
[ "$(restarts)" -gt "$r0" ] && ok "restart: on-failure did the work (restarts $r0 → $(restarts))" || bad "agent restart count increased"
wait_for 30 "the API issues credentials again, without being restarted" api_works

echo
echo "2. make rotate-now"
old=$(secret_accessor)
make --no-print-directory rotate-now >/dev/null
new_secret() { [ "$(secret_accessor)" != "$old" ]; }
wait_for 30 "the rotator issues a new secret-id" new_secret
accessor_dead "$old" && ok "the replaced secret-id is destroyed in Vault" || bad "the replaced secret-id is destroyed in Vault"
agent_token_ok && ok "the agent's token is unaffected" || bad "the agent's token is unaffected"
api_works && ok "the API keeps working" || bad "the API keeps working"

echo
echo "3. Worst case: the secret-id is destroyed AND the token revoked"
old=$(secret_accessor)
vault write auth/approle/role/$ROLE/secret-id-accessor/destroy secret_id_accessor="$old" >/dev/null
vault token revoke -accessor "$(agent_accessor)" >/dev/null
wait_for 180 "the rotator notices Vault no longer knows the secret-id and issues a new one" new_secret
wait_for 240 "the agent logs in with the new secret-id, no human involved" agent_token_ok
wait_for 30 "the API issues credentials again" api_works

echo
echo "4. The rotator's own credential is destroyed"
rot_acc=$(vault write -field=secret_id_accessor auth/approle/role/secret-theatre-rotator/secret-id/lookup \
  secret_id="$(cat .secrets/vault/rotator/secret-id)")
vault write auth/approle/role/secret-theatre-rotator/secret-id-accessor/destroy secret_id_accessor="$rot_acc" >/dev/null
api_works && ok "the API keeps working (the rotator is not in its path)" || bad "the API keeps working"
# Capture first: doctor exits 1 when it finds a problem, and under pipefail
# `doctor | grep -q` would then fail even when grep matches.
doc=$(./scripts/doctor.sh 2>/dev/null)
grep -q "rotator's own credential is rejected" <<<"$doc" && ok "make doctor names it and the fix" || bad "make doctor names it"
./scripts/agents-recover.sh >/dev/null 2>&1
rotator_login() { podman exec srot-rotator sh -c 't=$(vault write -field=token auth/approle/login role_id="$(cat /run/rotator/role-id)" secret_id="$(cat /run/rotator/secret-id)" 2>/dev/null) && VAULT_TOKEN=$t vault token revoke -self >/dev/null 2>&1'; }
wait_for 30 "make agents-recover re-issues it and the rotator logs in" rotator_login
old=$(secret_accessor)
make --no-print-directory rotate-now >/dev/null
wait_for 30 "the rotator can rotate again" new_secret
unset VAULT_TOKEN

echo
echo "5. The seal token vault-1 is running on is revoked (on vault-s)"
seal_agent_ok() { podman exec srot-seal-agent sh -c 'VAULT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null) vault token lookup >/dev/null 2>&1'; }
# The accessor of the token vault-1's process holds, looked up from inside
# vault-1 so the token itself never leaves the container.
held_acc=$(podman exec srot-vault-1 sh -c 'VAULT_TOKEN=$(tr "\0" "\n" </proc/1/environ | sed -n "s/^VAULT_TOKEN=//p") VAULT_ADDR=https://vault-s:8200 VAULT_CACERT=/vault/config/tls/ca-chain.pem vault token lookup -format=json' | jq -r .data.accessor)
vault_node vault-s
vault_root seal
vault token revoke -accessor "$held_acc" >/dev/null
unset VAULT_TOKEN
api_works && ok "vault-1 keeps serving (the seal token is only needed to unseal)" || bad "vault-1 keeps serving"
./scripts/seal-token-status.sh >/dev/null 2>&1 && bad "seal-token-status flags the revoked token" || ok "seal-token-status flags the revoked token"
doc=$(./scripts/doctor.sh 2>/dev/null)
grep -q "seal token REJECTED" <<<"$doc" && ok "make doctor names it and the fix" || bad "make doctor names it"
wait_for 180 "the seal agent re-authenticates and holds a fresh token" seal_agent_ok
make --no-print-directory vault-recreate >/dev/null 2>&1
vault_node vault-1
vault_wait active 60 >/dev/null 2>&1 && ok "make vault-recreate: vault-1 unseals with the agent's fresh token" || bad "vault-1 unseals after recreate"
# Capture first: `podman logs | grep -q` fails under pipefail (SIGPIPE).
vlog=$(podman logs srot-vault-1 2>&1)
grep -q 'seal token: seal agent sink' <<<"$vlog" && ok "vault-1 started on the seal agent's token, not the fallback" || bad "vault-1 started on the seal agent's token"
./scripts/seal-token-status.sh >/dev/null 2>&1 && ok "seal-token-status is clean again" || bad "seal-token-status is clean again"
wait_for 60 "the lanes work again" api_works

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
