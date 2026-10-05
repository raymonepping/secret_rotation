# The three lanes' Vault side: one database mount, one connection, a dynamic
# role (Patient), a static role (Surgeon). The Doctor lane rotates the
# connection's own credential.
#
# sslmode=disable: PostgreSQL and Vault share the internal Podman network in
# this lab. A production deployment uses verify-full.

resource "vault_mount" "database" {
  path = "database"
  type = "database"
}

resource "vault_database_secret_backend_connection" "hospital" {
  backend       = vault_mount.database.path
  name          = var.connection_name
  allowed_roles = [var.dynamic_role, var.static_role]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${var.postgres_host}/${var.db_name}?sslmode=disable"
    username       = var.mgmt_user
    password       = var.mgmt_password
  }

  lifecycle {
    # After a root rotation only Vault knows the password. Terraform must
    # never write the stale initial value back.
    ignore_changes = [postgresql[0].password]
  }
}

# Patient: a fresh PostgreSQL role per request, dropped when the lease ends.
resource "vault_database_secret_backend_role" "patient" {
  backend = vault_mount.database.path
  name    = var.dynamic_role
  db_name = vault_database_secret_backend_connection.hospital.name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT CONNECT ON DATABASE ${var.db_name} TO \"{{name}}\";",
    "GRANT SELECT ON patient_status_demo TO \"{{name}}\";",
  ]
  revocation_statements = [
    "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";",
    "REVOKE CONNECT ON DATABASE ${var.db_name} FROM \"{{name}}\";",
    # A pulse check may still hold a session; end it so the role can go.
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '{{name}}';",
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]
  default_ttl = var.dynamic_ttl
  max_ttl     = var.dynamic_max_ttl
}

# Surgeon: an existing account whose password Vault owns and rotates.
resource "vault_database_secret_backend_static_role" "surgeon" {
  backend         = vault_mount.database.path
  name            = var.static_role
  db_name         = vault_database_secret_backend_connection.hospital.name
  username        = var.static_user
  rotation_period = var.static_rotation_period
}
