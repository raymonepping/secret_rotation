#!/bin/sh
# postgres/init/02-roles.sh — the two accounts Vault works with. Runs once, on
# an empty volume. Passwords are read from a mounted file, not the
# environment, and passed to psql as variables (never in a command line).
#
#   vault_mgmt   Vault's connection user. CREATEROLE (creates and drops the
#                patient roles), CONNECT and SELECT with grant option (hands
#                them on), ADMIN on surgeon_svc (rotates its password). Not a
#                superuser: rotating its password ("rotate root") is safe.
#   surgeon_svc  The static role's account. Vault rotates its password.
set -eu

. /run/secrets/postgres.env
: "${VAULT_MGMT_PASSWORD:?missing in postgres.env}"
: "${SURGEON_SVC_PASSWORD:?missing in postgres.env}"

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$SROT_DB_NAME" \
  -v db="$SROT_DB_NAME" -v mgmt="$SROT_DB_MGMT_USER" -v svc="$SROT_DB_STATIC_USER" \
  -v mgmt_pw="$VAULT_MGMT_PASSWORD" -v svc_pw="$SURGEON_SVC_PASSWORD" <<'SQL'
CREATE ROLE :"mgmt" WITH LOGIN CREATEROLE PASSWORD :'mgmt_pw';
GRANT CONNECT ON DATABASE :"db" TO :"mgmt" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA public TO :"mgmt";
GRANT SELECT ON patient_status_demo TO :"mgmt" WITH GRANT OPTION;

CREATE ROLE :"svc" WITH LOGIN PASSWORD :'svc_pw';
GRANT CONNECT ON DATABASE :"db" TO :"svc";
GRANT SELECT ON patient_status_demo TO :"svc";
-- PostgreSQL 16: altering another role's password needs ADMIN on it.
-- INHERIT/SET FALSE: vault_mgmt administers surgeon_svc, it does not become it.
GRANT :"svc" TO :"mgmt" WITH ADMIN TRUE, INHERIT FALSE, SET FALSE;
SQL
echo "02-roles: created $SROT_DB_MGMT_USER and $SROT_DB_STATIC_USER"
