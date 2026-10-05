#!/bin/sh
# scripts/vault-server.sh — entrypoint of both Vault server containers.
set -eu

# The Transit seal token is delivered as a file, never as an environment
# variable in a compose file. vault-s has neither file (Shamir seal). It is
# read once, here: a replaced token is used from the next start on.
#
#   /run/secrets/seal/transit-token  seal agent sink (identity seal-autounseal,
#                                    kept fresh by srot-seal-agent). Preferred.
#   /run/secrets/transit-token       issued by `make vault-bootstrap`. Used on
#                                    the very first start, before the seal
#                                    agent exists, and as a fallback.
#
# A dead token in the sink must not crash-loop the node (an expired seal
# token looks exactly like a flapping healthcheck), so the sink token is
# checked against vault-s first and skipped only if vault-s REJECTS it.
SEAL_ADDR="https://vault-s:8200"
CA=/vault/config/tls/ca-chain.pem
pick_token() {
  if [ -s /run/secrets/seal/transit-token ]; then
    t=$(cat /run/secrets/seal/transit-token)
    if out=$(VAULT_ADDR=$SEAL_ADDR VAULT_CACERT=$CA VAULT_TOKEN=$t vault token lookup 2>&1); then
      echo "[vault-server] seal token: seal agent sink" >&2
      printf '%s' "$t"
      return 0
    fi
    if printf '%s' "$out" | grep -qiE "permission denied|invalid token|bad token"; then
      echo "[vault-server] the seal agent's token was REJECTED by vault-s; falling back to the bootstrap token" >&2
    else
      # vault-s unreachable or sealed: the token cannot be judged; use it.
      # The seal retries until vault-s is back.
      echo "[vault-server] seal token: seal agent sink (vault-s not reachable to verify)" >&2
      printf '%s' "$t"
      return 0
    fi
  fi
  if [ -s /run/secrets/transit-token ]; then
    echo "[vault-server] seal token: bootstrap file" >&2
    cat /run/secrets/transit-token
    return 0
  fi
  return 1
}
if [ -e /run/secrets/transit-token ] || [ -d /run/secrets/seal ]; then
  VAULT_TOKEN=$(pick_token) || {
    echo '[vault-server] no Transit seal token available; run make vault-bootstrap.' >&2
    exit 1
  }
  export VAULT_TOKEN
fi

# Data and audit live in named volumes. Make sure the audit file exists and
# is writable before Vault starts, so enabling the audit device never fails
# on a fresh volume.
mkdir -p /vault/file /vault/audit
touch /vault/audit/vault-audit.log
exec vault server -config=/vault/config/config.hcl
