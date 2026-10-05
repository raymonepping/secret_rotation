#!/usr/bin/env bash
# scripts/clean-slate.sh — start over: remove this lab's containers and
# persistent volumes, and move the credentials that belonged to them aside.
#
# Takes a backup first when the stack is running (refuses to continue if that
# backup fails, unless SKIP_BACKUP=1). Asks for DELETE to be typed; CONFIRM=DELETE
# in the environment answers for scripts. TLS material and .env are kept.
# Afterwards `make bootstrap` builds everything again from zero.
set -euo pipefail
umask 077
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
cd "$SROT_ROOT"

containers=$(podman ps -a --filter name=^srot- --format '{{.Names}}')
volumes=$(podman volume ls -q --filter name=^srot- || true)

echo "clean-slate will remove:"
echo "  containers: $(echo $containers)"
echo "  volumes:    $(echo $volumes)"
echo "and move init files, Transit token, the rotator credentials, Terraform state"
echo "and postgres.env to .secrets/legacy/. TLS material and .env are kept."
answer=${CONFIRM:-}
if [ -z "$answer" ]; then
  printf 'Type DELETE to continue: '
  read -r answer
fi
[ "$answer" = DELETE ] || { echo "clean-slate: aborted, nothing changed."; exit 1; }

if [ "${SKIP_BACKUP:-0}" != 1 ] && [ "$(srot_container_state srot-vault-1)" = running ] && [ -s "$SROT_STATE/vault-init.json" ]; then
  "$SROT_ROOT/scripts/backup.sh" || {
    echo "clean-slate: backup failed; nothing removed. SKIP_BACKUP=1 to start over without one." >&2
    exit 1
  }
fi

for c in $containers; do podman rm -f "$c" >/dev/null && echo "clean-slate: removed container $c"; done
for v in $volumes; do podman volume rm "$v" >/dev/null && echo "clean-slate: removed volume $v"; done

legacy=".secrets/legacy/$(date +%Y-%m-%d)/clean-slate-$(date +%H%M%S)"
mkdir -p "$legacy"
for f in .secrets/vault/seal-init.json .secrets/vault/vault-init.json .secrets/vault/transit-token \
  .secrets/vault/approle-api .secrets/vault/rotator .secrets/vault/seal-rotator .secrets/terraform/vault-seal.tfstate .secrets/terraform/vault-seal.tfstate.backup .secrets/terraform/vault-platform.tfstate .secrets/terraform/vault-database.tfstate \
  .secrets/terraform/vault-platform.tfstate.backup .secrets/terraform/vault-database.tfstate.backup .secrets/postgres.env; do
  [ -e "$f" ] && mv "$f" "$legacy/" && echo "clean-slate: moved ${f#.secrets/} to ${legacy#.secrets/}/"
done
echo "clean-slate: done. Run make bootstrap."
