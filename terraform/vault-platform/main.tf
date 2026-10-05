terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
  # State holds secrets; it lives outside the code tree, mode 0600.
  backend "local" {
    path = "../../.secrets/terraform/vault-platform.tfstate"
  }
}

# Address, CA and token come from the environment (VAULT_ADDR, VAULT_CACERT,
# VAULT_TOKEN), exported by scripts/tf.sh. Never run terraform here directly.
provider "vault" {}

variable "network_cidr" {
  description = "Subnet of srot-internal; the API's AppRole only works from there (scripts/tf.sh reads it from Podman)"
  type        = string
}

# The file audit device is owned by scripts/vault-bootstrap.sh: it has to
# exist before anything else (Terraform included) talks to vault-1.

resource "vault_auth_backend" "approle" {
  type = "approle"
  path = "approle"

  # AppRole caps every secret-id (and token) at the mount's effective
  # max_lease_ttl. Untuned that is vault-1's server-wide max_lease_ttl (24h),
  # so a role declaring a 90-day secret_id_ttl would silently get 24 hours —
  # the bug that broke Durin and Editors Factory on 2026-09-30. Raising the
  # ceiling on this mount only keeps every other mount's 24h maximum.
  tune {
    default_lease_ttl = "1h"
    max_lease_ttl     = "2160h" # 90 days = the secret_id_ttl the API role declares
  }
}

variable "db_names" {
  description = "Names the API policy grants access to (config/defaults.env, via scripts/tf.sh)"
  type = object({
    dynamic_role = string
    static_role  = string
    connection   = string
  })
}

resource "vault_policy" "api" {
  name   = "secret-theatre-api"
  policy = templatefile("${path.module}/../../vault/policies/secret-theatre-api.hcl.tftpl", var.db_names)
}

# The API's machine identity. A Vault Agent in compose/app logs in with it and
# keeps a token file fresh; the API only reads that file.
resource "vault_approle_auth_backend_role" "api" {
  backend   = vault_auth_backend.approle.path
  role_name = "secret-theatre-api"
  # Full list, always: a partial list silently detaches the rest.
  token_policies = ["default", vault_policy.api.name]
  token_ttl      = 900
  token_max_ttl  = 3600
  # The rotator (compose/app/rotator) replaces it below 1/3 of the life Vault
  # reports, so it is never this old.
  secret_id_ttl         = var.api_secret_id_ttl
  token_bound_cidrs     = [var.network_cidr]
  secret_id_bound_cidrs = [var.network_cidr]
}

variable "api_secret_id_ttl" {
  description = "Lifetime of the API identity's secret-id, in seconds (the mount tune above must allow it)"
  type        = number
  default     = 7776000 # 90 days
}

# ── The rotator's identity ───────────────────────────────────────────────────
# The one machine credential a human (make rotator-bootstrap) hands over. It
# may only manage the API role's secret-ids: read the role-id, issue, look up
# and destroy secret-ids. It can read no secret.
resource "vault_policy" "rotator" {
  name   = "secret-theatre-rotator"
  policy = <<-EOT
    # secret-theatre-rotator — keeps ${vault_approle_auth_backend_role.api.role_name}'s secret-id valid.
    path "auth/approle/role/${vault_approle_auth_backend_role.api.role_name}/role-id" {
      capabilities = ["read"]
    }
    path "auth/approle/role/${vault_approle_auth_backend_role.api.role_name}/secret-id" {
      capabilities = ["create", "update"]
    }
    path "auth/approle/role/${vault_approle_auth_backend_role.api.role_name}/secret-id/lookup" {
      capabilities = ["create", "update"]
    }
    path "auth/approle/role/${vault_approle_auth_backend_role.api.role_name}/secret-id-accessor/destroy" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_approle_auth_backend_role" "rotator" {
  backend   = vault_auth_backend.approle.path
  role_name = "secret-theatre-rotator"
  # Full list: the rotator needs no default policy beyond its own.
  token_policies = [vault_policy.rotator.name]
  token_ttl      = 300
  token_max_ttl  = 600
  # Lab: the bootstrap credential does not expire; make agents-recover
  # re-issues it if it is ever destroyed.
  secret_id_ttl         = 0
  token_bound_cidrs     = [var.network_cidr]
  secret_id_bound_cidrs = [var.network_cidr]
}

data "vault_approle_auth_backend_role_id" "api" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.api.role_name
}

output "api_role_id" {
  value = data.vault_approle_auth_backend_role_id.api.role_id
}
