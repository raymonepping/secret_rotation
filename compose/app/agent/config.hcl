# Vault Agent for the API's identity (AppRole secret-theatre-api).
# Logs in with the role-id and secret-id the rotator keeps valid and keeps
# a token file fresh for the API. The API never sees the AppRole credentials.
pid_file = "/tmp/pidfile"

vault {
  address = "https://vault-1:8200"
  ca_cert = "/vault/tls/ca-chain.pem"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    # A failed login (secret-id destroyed, rotator about to replace it) is
    # retried with backoff; the default ceiling is 5 minutes. 30s keeps the
    # worst case at about one rotator pass.
    min_backoff = "2s"
    max_backoff = "30s"
    config = {
      role_id_file_path                   = "/run/approle/secret-theatre-api/role-id"
      secret_id_file_path                 = "/run/approle/secret-theatre-api/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/vault/secrets/token"
      # gid 1000 is the API container's group.
      mode = 0640
    }
  }
}
