#!/usr/bin/env bash
# scripts/env-init.sh — create .env from .env.example and fill every empty
# *_PASSWORD with a random value. Never overwrites a value that is set.
set -euo pipefail
umask 077
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$ROOT/.env"

[ -s "$env_file" ] || { cp "$ROOT/.env.example" "$env_file"; echo "env-init: created .env from .env.example"; }
chmod 600 "$env_file"

filled=0
while IFS= read -r name; do
  value=$(grep -E "^${name}=" "$env_file" | tail -1 | cut -d= -f2-)
  [ -z "$value" ] || continue
  tmp=$(mktemp "$ROOT/.env.XXXXXX")
  awk -v n="$name" -v v="$(openssl rand -hex 24)" -F= '$1 == n && $2 == "" {print n "=" v; next} {print}' "$env_file" >"$tmp"
  cat "$tmp" >"$env_file"
  rm -f "$tmp"
  echo "env-init: generated $name"
  filled=$((filled + 1))
done < <(grep -oE '^[A-Z0-9_]+_PASSWORD=' "$env_file" | tr -d '=')

[ "$filled" -gt 0 ] || echo "env-init: .env is complete — nothing to do"
