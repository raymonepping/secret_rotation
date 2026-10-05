#!/usr/bin/env bash
# scripts/tf.sh <root> <plan|apply|destroy|output> [terraform args…]
#
# The only supported way to run Terraform here. Exports vault-1's address,
# the CA and a token, and never echoes the token.
#
# Lab shortcut: the token is the target node's root token from
# .secrets/vault/<seal|vault>-init.json (vault-seal targets vault-s). A production setup gives Terraform its own
# scoped, short-lived identity (vault_reference uses a tf-admin Vault Agent).
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"

root=${1:?Usage: tf.sh <root> <plan|apply|destroy|output> [args]}
action=${2:?Usage: tf.sh <root> <plan|apply|destroy|output> [args]}
shift 2
dir="$SROT_ROOT/terraform/$root"
[ -f "$dir/main.tf" ] || { echo "tf: unknown root '$root'" >&2; exit 64; }

case "$root" in
vault-seal) vault_node vault-s; vault_root seal ;;
*) vault_node vault-1; vault_root vault ;;
esac
export VAULT_ADDR VAULT_CACERT VAULT_TOKEN

# Root-specific inputs, from local files and Podman; never from the command line.
case "$root" in
vault-seal)
  TF_VAR_network_cidr=$(podman network inspect srot-internal --format '{{(index .Subnets 0).Subnet}}')
  export TF_VAR_network_cidr
  ;;
vault-platform)
  TF_VAR_network_cidr=$(podman network inspect srot-internal --format '{{(index .Subnets 0).Subnet}}')
  TF_VAR_db_names=$(jq -nc --arg d "$(srot_conf SROT_DB_ROLE_DYNAMIC)" --arg s "$(srot_conf SROT_DB_ROLE_STATIC)" \
    --arg c "$(srot_conf SROT_DB_CONNECTION)" '{dynamic_role: $d, static_role: $s, connection: $c}')
  export TF_VAR_network_cidr TF_VAR_db_names
  ;;
vault-database)
  pg_env="$SROT_ROOT/.secrets/postgres.env"
  [ -s "$pg_env" ] || { echo "tf: .secrets/postgres.env is missing — run make data-up first" >&2; exit 1; }
  TF_VAR_mgmt_password=$(grep -E '^VAULT_MGMT_PASSWORD=' "$pg_env" | cut -d= -f2-)
  TF_VAR_db_name=$(srot_conf SROT_DB_NAME)
  TF_VAR_connection_name=$(srot_conf SROT_DB_CONNECTION)
  TF_VAR_mgmt_user=$(srot_conf SROT_DB_MGMT_USER)
  TF_VAR_dynamic_role=$(srot_conf SROT_DB_ROLE_DYNAMIC)
  TF_VAR_static_role=$(srot_conf SROT_DB_ROLE_STATIC)
  TF_VAR_static_user=$(srot_conf SROT_DB_STATIC_USER)
  export TF_VAR_mgmt_password TF_VAR_db_name TF_VAR_connection_name TF_VAR_mgmt_user \
    TF_VAR_dynamic_role TF_VAR_static_role TF_VAR_static_user
  ;;
esac

mkdir -p "$SROT_ROOT/.secrets/terraform"
chmod 700 "$SROT_ROOT/.secrets/terraform"
cd "$dir"
terraform init -input=false >/dev/null

# vault-database: after `make db-rotate-root` only Vault knows vault_mgmt's
# password. When the connection has to be created (again), reset that
# password through the PostgreSQL superuser first and hand Terraform the new
# value; Vault rotates it away again on the next root rotation.
if [ "$root" = vault-database ] && [ "$action" = apply ]; then
  # Read once into a variable: `terraform state list | grep -q` fails under
  # pipefail when grep exits early.
  in_state=$(terraform state list 2>/dev/null || true)
  if ! grep -q 'vault_database_secret_backend_connection.hospital' <<<"$in_state"; then
    newpw=$(openssl rand -hex 24)
    # From stdin: psql does not expand :'pw' inside -c.
    podman exec -i srot-postgres psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres \
      -v pw="$newpw" -v u="$TF_VAR_mgmt_user" <<<"ALTER ROLE :\"u\" PASSWORD :'pw';"
    tmp=$(mktemp "$pg_env.XXXXXX")
    grep -v '^VAULT_MGMT_PASSWORD=' "$pg_env" >"$tmp"
    echo "VAULT_MGMT_PASSWORD=$newpw" >>"$tmp"
    mv "$tmp" "$pg_env"
    TF_VAR_mgmt_password=$newpw
    export TF_VAR_mgmt_password
    echo "tf: $TF_VAR_mgmt_user password reset for the new connection (make db-rotate-root makes it Vault-only)"
  fi
fi

case "$action" in
plan) terraform plan -input=false -detailed-exitcode "$@" ;;
apply) terraform apply -input=false -auto-approve "$@" ;;
destroy) terraform destroy -input=false -auto-approve "$@" ;;
output) terraform output "$@" ;;
*) echo "tf: unknown action '$action'" >&2; exit 64 ;;
esac
