# vault-1 — the application Vault. Auto-unseals through vault-s's Transit key.
# Single-node Raft (decision D2); a second node only needs its own config with
# a retry_join pointing here.
ui            = true
disable_mlock = true

api_addr     = "https://vault-1:8200"
cluster_addr = "https://vault-1:8201"

default_lease_ttl = "1h"
max_lease_ttl     = "24h"

# The token is not here: scripts/vault-server.sh exports VAULT_TOKEN from the
# file mounted at /run/secrets/transit-token (written by make vault-bootstrap).
seal "transit" {
  address     = "https://vault-s:8200"
  key_name    = "autounseal"
  mount_path  = "transit/"
  tls_ca_cert = "/vault/config/tls/ca-chain.pem"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_cert_file   = "/vault/config/tls/vault.crt"
  tls_key_file    = "/vault/config/tls/vault.key"
  tls_min_version = "tls13"
}

storage "raft" {
  path    = "/vault/file"
  node_id = "vault-1"
}

log_level = "warn"
