#!/usr/bin/env bash
# scripts/verify.sh [section…] — end-to-end checks. Read-only apart from
# short-lived credentials it issues and revokes itself. Never prints a token
# or password. Sections: vault (default: all).
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
cd "$SROT_ROOT"

pass=0
fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail + 1)); }
check() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then ok "$msg"; else bad "$msg"; fi; }
# A container started seconds ago reports "starting" until its first check
# passes; give it up to 30s before calling it unhealthy.
healthy() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(podman container inspect "$1" --format '{{.State.Health.Status}}' 2>/dev/null)" = healthy ] && return 0
    sleep 3
  done
  return 1
}

section_vault() {
  echo "vault"
  check "certificate chain verifies" openssl verify -CAfile vault-tls/ca-chain.pem vault-tls/vault.crt
  check "srot-vault-s healthy" healthy srot-vault-s
  check "srot-vault-1 healthy" healthy srot-vault-1
  vault_node vault-s
  local s
  s=$(vault_json 2>/dev/null || echo '{}')
  check "vault-s initialized and unsealed" jq -e '.initialized and (.sealed | not)' <<<"$s"
  check "vault-s seal type is shamir" jq -e '.type == "shamir"' <<<"$s"
  vault_root seal
  check "vault-s audit device enabled" bash -c 'vault audit list -format=json | jq -e "has(\"file/\")"'
  check "vault-s transit key autounseal exists" vault read transit/keys/autounseal
  unset VAULT_TOKEN
  vault_node vault-1
  s=$(vault_json 2>/dev/null || echo '{}')
  check "vault-1 initialized and unsealed" jq -e '.initialized and (.sealed | not)' <<<"$s"
  check "vault-1 seal type is transit (auto-unseal via vault-s)" jq -e '.type == "transit"' <<<"$s"
  check "vault-1 is the active node" bash -c 'curl -sf --cacert "$VAULT_CACERT" "$VAULT_ADDR/v1/sys/leader" | jq -e .is_self'
  vault_root vault
  check "vault-1 audit device enabled" bash -c 'vault audit list -format=json | jq -e "has(\"file/\")"'
  unset VAULT_TOKEN

  # Seal plane identity (prompt 08.01).
  check "srot-seal-rotator healthy" healthy srot-seal-rotator
  check "srot-seal-agent healthy" healthy srot-seal-agent
  local st meta acc life
  st=$("$SROT_ROOT/scripts/seal-token-status.sh" 2>/dev/null || true)
  if grep -q "valid (source: seal agent sink)" <<<"$st"; then ok "vault-1 runs on the seal agent's token, and vault-s accepts it"; else bad "vault-1 runs on the seal agent's token ($st)"; fi
  vault_node vault-s
  vault_root seal
  meta=$(podman exec srot-seal-rotator cat /run/approle/seal-autounseal/metadata.json 2>/dev/null || echo '{}')
  acc=$(jq -r '.secret_id_accessor // empty' <<<"$meta")
  life=$(vault write -format=json auth/approle/role/seal-autounseal/secret-id-accessor/lookup secret_id_accessor="$acc" 2>/dev/null |
    jq -r '((.data.expiration_time | sub("\\.[0-9]+Z$"; "Z") | fromdate) - (.data.creation_time | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 86400 | floor' 2>/dev/null || echo 0)
  if [ "${life:-0}" -ge 89 ]; then ok "seal-autounseal secret-id lives ${life} days (vault-s approle tune holds)"; else bad "seal-autounseal secret-id lives ≥ 89 days (got ${life:-?})"; fi
  unset VAULT_TOKEN
}

# pg_login <user> <password> [sql] — log in the way Vault and the API do:
# over the network address. The image's pg_hba.conf trusts the socket and
# 127.0.0.1, so a login there accepts any password and proves nothing.
pg_login() {
  podman exec -e PGPASSWORD="$2" srot-postgres \
    psql -h postgres -U "$1" -d "$(srot_conf SROT_DB_NAME)" -tAc "${3:-SELECT 1}"
}
pg_role_exists() {
  [ "$(podman exec srot-postgres psql -U postgres -tAc "SELECT count(*) FROM pg_roles WHERE rolname = '$1'")" = 1 ]
}

section_database() {
  echo "database"
  local dyn stat conn creds user pw lease out
  dyn=$(srot_conf SROT_DB_ROLE_DYNAMIC)
  stat=$(srot_conf SROT_DB_ROLE_STATIC)
  conn=$(srot_conf SROT_DB_CONNECTION)
  check "srot-postgres healthy" healthy srot-postgres
  vault_node vault-1
  vault_root vault
  check "mount database/ exists" bash -c 'vault secrets list -format=json | jq -e "has(\"database/\")"'
  check "connection $conn exists" vault read "database/config/$conn"
  check "dynamic role $dyn exists" vault read "database/roles/$dyn"
  check "static role $stat exists" vault read "database/static-roles/$stat"

  # Patient: issue, use, revoke, gone.
  if creds=$(vault read -format=json "database/creds/$dyn" 2>/dev/null); then
    ok "dynamic credential issued (ttl $(jq -r .lease_duration <<<"$creds")s)"
    user=$(jq -r .data.username <<<"$creds")
    pw=$(jq -r .data.password <<<"$creds")
    lease=$(jq -r .lease_id <<<"$creds")
    out=$(pg_login "$user" "$pw" 'SELECT count(*) FROM patient_status_demo' 2>/dev/null || true)
    if [ -n "$out" ] && [ "$out" -gt 0 ] 2>/dev/null; then ok "dynamic credential connects and reads $out rows"; else bad "dynamic credential connects and reads"; fi
    check "lease revoked" vault lease revoke "$lease"
    if pg_login "$user" "$pw" >/dev/null 2>&1; then bad "revoked credential is refused"; else ok "revoked credential is refused"; fi
    if pg_role_exists "$user"; then bad "revoked role dropped from PostgreSQL"; else ok "revoked role dropped from PostgreSQL"; fi
  else
    bad "dynamic credential issued"
  fi

  # Surgeon: the static account's current password works.
  if creds=$(vault read -format=json "database/static-creds/$stat" 2>/dev/null); then
    user=$(jq -r .data.username <<<"$creds")
    pw=$(jq -r .data.password <<<"$creds")
    if pg_login "$user" "$pw" >/dev/null 2>&1; then ok "static credential ($user) connects"; else bad "static credential ($user) connects"; fi
  else
    bad "static credential readable"
  fi

  # Doctor: once root was rotated, the initial password must be dead.
  pw=$(grep -E '^VAULT_MGMT_PASSWORD=' .secrets/postgres.env | cut -d= -f2-)
  if pg_login "$(srot_conf SROT_DB_MGMT_USER)" "$pw" >/dev/null 2>&1; then
    echo "  · root not rotated yet: the initial $(srot_conf SROT_DB_MGMT_USER) password still works (make db-rotate-root)"
  else
    ok "root rotated: the initial $(srot_conf SROT_DB_MGMT_USER) password is refused"
  fi
  unset VAULT_TOKEN pw
}

# api <METHOD> <path> [json] — call the API through nginx, the way the UI does.
# Prints the body; the HTTP status goes to $API_STATUS_FILE.
API_STATUS_FILE=$(mktemp)
trap 'rm -f "$API_STATUS_FILE"' EXIT
api() {
  curl -s -o /dev/stdout -w '%{http_code}' -X "$1" -H 'Content-Type: application/json' \
    ${3:+--data "$3"} "http://127.0.0.1:$(srot_conf SROT_PORT_WEB)$2" | {
    body=$(cat)
    printf '%s' "${body: -3}" >"$API_STATUS_FILE"
    printf '%s' "${body%???}"
  }
}
status_is() { [ "$(cat "$API_STATUS_FILE")" = "$1" ]; }
creds_json() { jq -c '{username, password}' <<<"$1"; }

section_app() {
  echo "app"
  local out c old new p
  check "srot-rotator healthy" healthy srot-rotator
  check "srot-vault-agent healthy" healthy srot-vault-agent

  # The identity chain (Durin's pattern): rotator → secret-id → agent → token.
  vault_node vault-1
  vault_root vault
  local meta life acc rt
  meta=$(podman exec srot-rotator cat /run/approle/secret-theatre-api/metadata.json 2>/dev/null || echo '{}')
  acc=$(jq -r '.secret_id_accessor // empty' <<<"$meta")
  life=$(vault write -format=json auth/approle/role/secret-theatre-api/secret-id-accessor/lookup secret_id_accessor="$acc" 2>/dev/null |
    jq -r '((.data.expiration_time | sub("\\.[0-9]+Z$"; "Z") | fromdate) - (.data.creation_time | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 86400 | floor' 2>/dev/null || echo 0)
  if [ "${life:-0}" -ge 89 ]; then ok "API secret-id issued by the rotator lives ${life} days (the approle mount tune holds)"; else bad "API secret-id lives ≥ 89 days (got ${life:-?}; vault read sys/auth/approle/tune)"; fi
  rt=$(podman exec srot-rotator sh -c 'vault write -field=token auth/approle/login role_id="$(cat /run/rotator/role-id)" secret_id="$(cat /run/rotator/secret-id)"' 2>/dev/null)
  if [ -n "$rt" ]; then
    ok "the rotator can log in with its own credential"
    if VAULT_TOKEN=$rt vault read "database/creds/$(srot_conf SROT_DB_ROLE_DYNAMIC)" >/dev/null 2>&1; then bad "the rotator's token cannot read secrets"; else ok "the rotator's token cannot read secrets"; fi
    VAULT_TOKEN=$rt vault token revoke -self >/dev/null 2>&1
  else
    bad "the rotator can log in with its own credential"
  fi
  unset VAULT_TOKEN
  check "srot-api healthy" healthy srot-api
  check "srot-web healthy" healthy srot-web
  # Capture first: under pipefail a SIGPIPE from `env | grep -q` would read
  # as "absent" exactly when the token IS there.
  local api_env
  api_env=$(podman exec srot-api env)
  if grep -q '^VAULT_TOKEN=' <<<"$api_env"; then bad "no VAULT_TOKEN in the API's environment"; else ok "no VAULT_TOKEN in the API's environment"; fi
  out=$(api GET /health)
  check "/health through nginx: token present" jq -e '.ok and .vault_token == "present"' <<<"$out"

  p=$(api GET /api/platform)
  check "/api/platform: vault-s unsealed" jq -e '.seal.reachable and (.seal.sealed | not)' <<<"$p"
  check "/api/platform: vault-1 unsealed and active" jq -e '.vault.reachable and (.vault.sealed | not) and (.vault.standby | not)' <<<"$p"
  check "/api/platform: postgres reachable" jq -e '.postgres.reachable' <<<"$p"
  check "/api/platform: agent identity valid, API policy attached" jq -e '.identity.valid and (.identity.policies | index("secret-theatre-api"))' <<<"$p"
  if grep -qE '"(token|client_token|id)"' <<<"$p"; then bad "/api/platform exposes no token"; else ok "/api/platform exposes no token"; fi

  # Patient: issue → pulse → revoke → flatline.
  c=$(api POST /api/patient/issue)
  if jq -e '.ok and .lease_duration > 0' <<<"$c" >/dev/null 2>&1; then
    ok "patient: dynamic credential issued (lease $(jq -r .lease_duration <<<"$c")s)"
    api POST /api/patient/test "$(creds_json "$c")" >/dev/null
    if status_is 200; then ok "patient: pulse confirmed"; else bad "patient: pulse confirmed"; fi
    out=$(api POST /api/patient/revoke "$(jq -c '{lease_id}' <<<"$c")")
    check "patient: lease revoked" jq -e '.ok and .status == "flatline"' <<<"$out"
    api POST /api/patient/test "$(creds_json "$c")" >/dev/null
    if status_is 401; then ok "patient: revoked credential has no pulse"; else bad "patient: revoked credential has no pulse"; fi
  else
    bad "patient: dynamic credential issued ($(jq -r '.error // empty' <<<"$c" 2>/dev/null))"
  fi

  # Surgeon: static credential works, rotate, old one dead, new one works.
  old=$(api POST /api/surgeon/issue)
  if jq -e '.ok and .rotation_period > 0' <<<"$old" >/dev/null 2>&1; then
    ok "surgeon: static credential loaded (rotates every $(jq -r .rotation_period <<<"$old")s)"
    api POST /api/surgeon/test "$(creds_json "$old")" >/dev/null
    if status_is 200; then ok "surgeon: static credential connects"; else bad "surgeon: static credential connects"; fi
    out=$(api POST /api/surgeon/rotate)
    check "surgeon: rotated on demand" jq -e '.ok' <<<"$out"
    new=$(api POST /api/surgeon/issue)
    if [ "$(jq -r .password <<<"$old")" != "$(jq -r .password <<<"$new")" ]; then ok "surgeon: password changed"; else bad "surgeon: password changed"; fi
    api POST /api/surgeon/test "$(creds_json "$old")" >/dev/null
    if status_is 401; then ok "surgeon: old password refused"; else bad "surgeon: old password refused"; fi
    api POST /api/surgeon/test "$(creds_json "$new")" >/dev/null
    if status_is 200; then ok "surgeon: new password connects"; else bad "surgeon: new password connects"; fi
  else
    bad "surgeon: static credential loaded ($(jq -r '.error // empty' <<<"$old" 2>/dev/null))"
  fi

  # Doctor: rotate root, and Vault can still do its job afterwards.
  out=$(api POST /api/doctor/rotate-root)
  check "doctor: root credential rotated" jq -e '.ok' <<<"$out"
  c=$(api POST /api/patient/issue)
  if jq -e '.ok' <<<"$c" >/dev/null 2>&1; then
    ok "doctor: Vault still issues credentials after the root rotation"
    api POST /api/patient/revoke "$(jq -c '{lease_id}' <<<"$c")" >/dev/null
  else
    bad "doctor: Vault still issues credentials after the root rotation"
  fi
}

sections=${*:-vault database app}
for s in $sections; do
  declare -F "section_$s" >/dev/null || { echo "verify: unknown section '$s'" >&2; exit 64; }
  "section_$s"
done
echo
echo "verify: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
