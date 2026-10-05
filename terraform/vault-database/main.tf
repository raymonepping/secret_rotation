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
    path = "../../.secrets/terraform/vault-database.tfstate"
  }
}

# Address, CA and token come from the environment (VAULT_ADDR, VAULT_CACERT,
# VAULT_TOKEN), exported by scripts/tf.sh. Never run terraform here directly.
provider "vault" {}
