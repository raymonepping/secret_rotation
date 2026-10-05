#!/usr/bin/env bash
# scripts/app-build.sh [api|web …] — build the app images with podman build.
#
# macOS provenance xattrs make the build context carry AppleDouble ._ files,
# which break JS builds ("Unexpected \x00"). Strip them, keep ._* in each
# .containerignore, and keep COPYFILE_DISABLE set.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
export COPYFILE_DISABLE=1

targets=${*:-api web}
for t in $targets; do
  ctx="$SROT_ROOT/app/$t"
  [ -f "$ctx/Containerfile" ] || { echo "app-build: unknown target '$t'" >&2; exit 64; }
  xattr -rc "$ctx" 2>/dev/null || true
  find "$ctx" -name '._*' -not -path '*/node_modules/*' -delete 2>/dev/null || true
  echo "app-build: building localhost/srot-$t:local"
  # --format docker: the OCI format drops HEALTHCHECK.
  podman build -q --format docker \
    --build-arg NODE_IMAGE="$(srot_conf NODE_IMAGE)" \
    --build-arg NGINX_IMAGE="$(srot_conf NGINX_IMAGE)" \
    -t "localhost/srot-$t:local" -f "$ctx/Containerfile" "$ctx" >/dev/null
done
