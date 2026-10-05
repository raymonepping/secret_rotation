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
    path = "../../.secrets/terraform/vault-seal.tfstate"
  }
}

# vault-s, with its root token (lab): exported by scripts/tf.sh.
provider "vault" {}

variable "network_cidr" {
  description = "Subnet of srot-internal; seal-plane identities may only log in from it"
  type        = string
}

# vault-s configuration beyond what scripts/vault-bootstrap.sh creates.
#
# The bootstrap owns what must exist before vault-1 can ever start: the
# transit mount, the `autounseal` key, the `autounseal` policy, the audit
# device and the fallback token. They are deliberately NOT managed here, so a
# `terraform destroy` of this root can never take the seal away from vault-1.

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Seal-plane machine identities (rotator, seal agent)"
  # AppRole caps secret-ids at the mount's maximum; vault-s's is 768h (32
  # days), below the 90 days the seal-autounseal role declares.
  tune {
    default_lease_ttl = "1h"
    max_lease_ttl     = "2160h"
  }
}

# The Transit seal token vault-1 starts with, kept fresh by srot-seal-agent.
resource "vault_approle_auth_backend_role" "seal_autounseal" {
  backend   = vault_auth_backend.approle.path
  role_name = "seal-autounseal"
  # Written by the bootstrap: encrypt/decrypt on transit/autounseal only.
  token_policies = ["autounseal"]
  # Periodic: lives as long as something renews it. The agent renews the one
  # in its sink, and vault-1's seal renews the one it started with, so a
  # token that was replaced in the sink keeps working until vault-1 restarts.
  token_period          = 86400
  secret_id_ttl         = 7776000 # 90 days; the seal rotator renews at 1/3
  token_bound_cidrs     = [var.network_cidr]
  secret_id_bound_cidrs = [var.network_cidr]
}

resource "vault_policy" "seal_rotator" {
  name   = "seal-rotator"
  policy = <<-EOT
    # seal-rotator — keeps ${vault_approle_auth_backend_role.seal_autounseal.role_name}'s secret-id valid. Nothing else.
    path "auth/approle/role/${vault_approle_auth_backend_role.seal_autounseal.role_name}/role-id" {
      capabilities = ["read"]
    }
    path "auth/approle/role/${vault_approle_auth_backend_role.seal_autounseal.role_name}/secret-id" {
      capabilities = ["create", "update"]
    }
    path "auth/approle/role/${vault_approle_auth_backend_role.seal_autounseal.role_name}/secret-id/lookup" {
      capabilities = ["create", "update"]
    }
    path "auth/approle/role/${vault_approle_auth_backend_role.seal_autounseal.role_name}/secret-id-accessor/destroy" {
      capabilities = ["create", "update"]
    }
  EOT
}

# The seal plane's one handed-over credential (make rotator-bootstrap).
resource "vault_approle_auth_backend_role" "seal_rotator" {
  backend               = vault_auth_backend.approle.path
  role_name             = "seal-rotator"
  token_policies        = [vault_policy.seal_rotator.name]
  token_ttl             = 300
  token_max_ttl         = 600
  secret_id_ttl         = 0
  token_bound_cidrs     = [var.network_cidr]
  secret_id_bound_cidrs = [var.network_cidr]
}
