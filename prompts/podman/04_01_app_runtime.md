# Prompt podman/04.01 — App runtime: Vault Agent, API and web in Podman

Read `prompts/podman/00_01_brief.md` first. Requires 03.01.

## Why this prompt exists

A demo about secret rotation should not run on a token copied into a
`.env` file. The API and the web app also still run as host processes with
mismatched ports (web on 5173, CORS allowing 3001), hardcoded database names
and an API base URL baked into each component. This prompt puts the app into
the stack, gives it a machine identity, and proves each lane end to end
through the HTTP API the UI uses.

## Goal

`make up` starts everything from a stopped machine. `make app-up` serves the
UI on `http://127.0.0.1:13001`, the API reaches Vault with a token it got
from a Vault Agent, and `make verify` drives all three lanes over HTTP.

## Reference

- `vault_reference/compose/common/agent/entrypoint.sh` (token watchdog)
- `vault_reference/compose/primary/agents/tf-admin/config.hcl`
- This repo: `app/api/src/routes/*.js`, `app/web/src/components/*.jsx`

## Deliverables

1. `make app-credentials`: reads the role-id from Terraform output, creates
   a secret-id with the root token, writes both to
   `.secrets/vault/approle-api/{role-id,secret-id}` (0600). Idempotent: keeps
   a secret-id Vault still accepts (`auth/approle/role/…/secret-id/lookup`).
2. `compose/app/compose.yaml`:
   - `srot-vault-agent`: Vault image, `user 100:1000`, read-only root,
     tmpfs `/tmp`, AppRole auto-auth from the bind-mounted credentials, file
     sink `/vault/secrets/token` mode 0640 on a volume shared with the API.
     Entrypoint adapted from vault_reference's watchdog (POSIX sh). The sink
     volume is ephemeral by intent: the agent removes a stale token at start.
     Healthcheck: a real `vault token lookup`, not file existence.
   - `srot-api`: built from `app/api/Containerfile` (node:24-alpine, `npm ci
     --omit=dev`, non-root user in group 1000, read-only root fs). Reads
     `VAULT_TOKEN_FILE`, `VAULT_ADDR=https://vault-1:8200`,
     `NODE_EXTRA_CA_CERTS` pointing at the mounted chain, `PGHOST=srot-postgres`,
     `PGDATABASE=hospital`, and the role/connection names. Depends on the
     agent being healthy. Port `127.0.0.1:${SROT_PORT_API}:3000`.
   - `srot-web`: `app/web/Containerfile`, multi-stage (node build, then
     `nginx:1.30.0-alpine` unprivileged config). nginx serves the build and
     proxies `/api/` and `/health` to `srot-api:3000` with a variable
     upstream and `resolver` so it starts before the API exists. Port
     `127.0.0.1:${SROT_PORT_WEB}:8080`.
3. API changes (behaviour of the lanes stays the same):
   - `src/vault.js`: one helper that reads the token file on every call,
     sends `X-Vault-Token`, and turns Vault errors into
     `{ ok:false, error, vault_status }`. The three routes use it; no route
     reads `process.env.VAULT_TOKEN`.
   - Names from env with the D4 defaults (`DB_ROLE_DYNAMIC`,
     `DB_ROLE_STATIC`, `DB_CONNECTION`).
   - `GET /api/platform`: unauthenticated `sys/health` of vault-s and
     vault-1 (seal state, version, HA), the PostgreSQL reachability, the
     agent token's TTL (from `auth/token/lookup-self`, no token value), and
     the configured role and connection names. The UI uses this in 05.01.
   - `GET /api/surgeon/issue` keeps working; additionally return
     `last_vault_rotation` and `rotation_period` (already present).
   - CORS: same-origin through nginx makes it unnecessary; keep it only for
     `npm run dev` on the configured web dev port, from env.
   - `/health` reports `vault_token: present|missing`, never the token.
4. Web changes: one `src/api.js` with `API_BASE = import.meta.env.VITE_API_BASE ?? ""`
   (empty = same origin). Components import it. Vite dev server proxies
   `/api` to `http://127.0.0.1:13000` so `npm run dev` still works.
5. Make targets: `app-build` (`COPYFILE_DISABLE=1`, strips xattrs first),
   `app-up` (credentials, build if images missing, up), `app-down`,
   `app-logs`, `app-rebuild` (build and recreate api + web), `up` (network,
   vault-up, data-up, app-up), `down` (app, data, vault; volumes kept),
   `open` (prints the URL).
6. `make verify`, section "app": agent healthy and its token valid; `/health`
   ok; patient issue → test ok → revoke → test fails; surgeon issue → test ok
   → rotate → old password fails, new one works; doctor rotate-root ok and a
   fresh patient credential still issues afterwards; `/api/platform` reports
   both Vault nodes unsealed. No token or password is printed.
7. `docs/STATE.md` updated.

## Design rules

- The API never sees a token in its environment. Only a file path.
- A dead agent token must heal without user action (watchdog restart).
- No `NODE_TLS_REJECT_UNAUTHORIZED=0`; Node trusts the lab CA through
  `NODE_EXTRA_CA_CERTS`.
- Keep the lane behaviour and the API contract the UI uses; add, do not
  rename.

## Validation

```bash
make up
make verify                              # vault, database, app sections pass
curl -s http://127.0.0.1:13001/api/platform | jq '.vault, .seal'
podman exec srot-api env | grep -c VAULT_TOKEN=     # 0
podman restart srot-vault-agent && sleep 20 && make verify
make down && make up && make verify      # cold start with the seal unseal step
```
