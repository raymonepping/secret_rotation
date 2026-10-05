SHELL := /bin/sh

.DEFAULT_GOAL := help

# First run:  make env-init && make bootstrap
# Daily:      make up / make down   (make up unseals vault-s for you)

# Compose stacks, one project each (srot-<stack>). See compose/README.md.
STACKS        := seal vault data app
# Stacks whose up/down need more than `compose up` get hand-written targets.
CUSTOM_STACKS := seal vault data app
NETWORK       := srot-internal

.PHONY: help check clock-sync status ps volumes network ports-check compose-config env-init gen-certs certs-reissue certs-status \
	vault-bootstrap unseal seal-up seal-token-status seal-down vault-up vault-down vault-status vault-recreate vault-login verify \
	data-up data-down psql tf-seal tf-platform tf-database tf-all tf-plan-all tf-destroy db-rotate-root db-test \
	rotator-bootstrap agents-status agents-recover rotate-now rotation-test app-build app-up app-down app-rebuild up down open \
	bootstrap doctor backup clean-slate \
	$(addsuffix -up,$(STACKS)) $(addsuffix -down,$(STACKS)) $(addsuffix -logs,$(STACKS))

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*## "; printf "Vault Secret Theatre — Podman + Make + Terraform\n"} \
	  /^# ── / {gsub(/─/, ""); gsub(/^# +| +$$/, ""); printf "\n%s\n", $$0} \
	  /^[a-zA-Z0-9_-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nStacks (each has <stack>-up, <stack>-down, <stack>-logs):\n  %s\n' "$(STACKS)"

# ── Podman ────────────────────────────────────────────────────────────────────

check: ## Verify Podman machine, compose provider, VM clock, memory and host tools
	@./scripts/podman-check.sh

status: ## Show this project's containers and network
	@podman ps -a --filter name=^srot- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
	@podman network exists $(NETWORK) && echo '$(NETWORK): present' || echo '$(NETWORK): not created'

ps: ## List this project's containers
	@podman ps -a --filter name=^srot-

volumes: ## List this project's named volumes and whether a container uses them
	@for v in $$(podman volume ls -q --filter name=^srot-); do \
		used=$$(podman ps -a --filter volume=$$v --format '{{.Names}}' | tr '\n' ' '); \
		data=$$(podman volume inspect $$v --format '{{index .Labels "io.srot.data"}}'); \
		printf '  %-34s %-11s %s\n' "$$v" "$${data:+persistent}" "$${used:-(unattached)}"; \
	done

network: ## (changes state) Create the srot-internal network if absent
	@./scripts/network.sh
	@echo "$(NETWORK): ready"

ports-check: ## Report host ports this stack wants that something else already holds
	@./scripts/ports-check.sh

compose-config: ## Validate every compose.yaml that exists
	@found=0; \
	for stack in $(STACKS); do \
		if [ -f "compose/$$stack/compose.yaml" ]; then \
			found=1; ./scripts/compose.sh "$$stack" config --quiet || exit $$?; \
			echo "compose/$$stack/compose.yaml: ok"; \
		fi; \
	done; \
	if [ "$$found" -eq 0 ]; then echo 'No compose.yaml files exist yet.'; fi

clock-sync: ## (changes state) Step the Podman VM's clock to the host's (after the Mac slept)
	@./scripts/clock-sync.sh

env-init: ## (changes state) Create .env and fill empty passwords; never overwrites
	@./scripts/env-init.sh

# ── Stacks ────────────────────────────────────────────────────────────────────

define STACK_TARGETS
$(1)-up: ## (changes state) Start the $(1) stack
	@./scripts/compose.sh "$(1)" config --quiet
	@$(MAKE) --no-print-directory network
	@./scripts/compose.sh "$(1)" up -d

$(1)-down: ## (changes state) Stop the $(1) stack; containers and volumes are kept
	@./scripts/compose.sh "$(1)" stop
endef

define STACK_LOGS
$(1)-logs: ## Follow $(1) logs
	@./scripts/compose.sh "$(1)" logs -f
endef

$(foreach stack,$(filter-out $(CUSTOM_STACKS),$(STACKS)),$(eval $(call STACK_TARGETS,$(stack))))
$(foreach stack,$(STACKS),$(eval $(call STACK_LOGS,$(stack))))

# ── TLS ───────────────────────────────────────────────────────────────────────

gen-certs: ## (changes state) Create the lab CA and the Vault listener certificate; idempotent
	@./scripts/gen-certs.sh

certs-reissue: ## (changes state) Re-sign the listener certificate and SIGHUP running nodes
	@./scripts/gen-certs.sh --reissue

certs-status: ## Show issuer, expiry and SANs of the listener certificate
	@./scripts/gen-certs.sh --status

# ── Vault ─────────────────────────────────────────────────────────────────────

vault-bootstrap: ## (changes state) Initialize vault-s and vault-1 on fresh volumes; idempotent
	@./scripts/vault-bootstrap.sh

unseal: ## (changes state) Unseal vault-s (idempotent); vault-1 then unseals itself
	@./scripts/vault-unseal.sh

seal-up: ## (changes state) Start vault-s, unseal it, then the seal rotator and seal agent
	@./scripts/seal-up.sh

seal-token-status: ## Is the seal token the running vault-1 holds still accepted by vault-s, and where is it from?
	@./scripts/seal-token-status.sh

seal-down: ## (changes state) Stop vault-s; vault-1 keeps running but cannot restart unsealed
	@./scripts/compose.sh seal stop

vault-up: ## (changes state) Cold start: vault-s, unseal, then vault-1 (auto-unseals)
	@test -s .secrets/vault/transit-token || { echo "No Transit token yet — run make vault-bootstrap first." >&2; exit 1; }
	@./scripts/seal-up.sh
	@./scripts/compose.sh vault up -d
	@./scripts/vault-wait.sh vault-1 active
	@./scripts/vault-status.sh

vault-down: ## (changes state) Stop vault-1, then vault-s (containers and volumes are kept)
	@./scripts/compose.sh vault stop 2>/dev/null || true
	@./scripts/compose.sh seal stop 2>/dev/null || true

vault-status: ## Show both Vault nodes: container, init, seal, HA role, Raft index, version
	@./scripts/vault-status.sh

vault-recreate: ## (changes state) Recreate vault-1 keeping its data: it starts on the seal agent's current token
	@bash -c '. ./scripts/common.sh && ensure_seal_token_volume'
	@./scripts/compose.sh vault up -d --force-recreate vault-1
	@./scripts/vault-wait.sh vault-1 active
	@./scripts/vault-status.sh

vault-login: ## Print the export line that points your shell's vault CLI at vault-1 (no token)
	@printf 'export VAULT_ADDR=https://127.0.0.1:%s VAULT_CACERT=%s\n' \
		"$$(bash -c '. ./scripts/common.sh && srot_conf SROT_PORT_VAULT_1')" "$(CURDIR)/vault-tls/ca-chain.pem"
	@echo "# then: vault login   (lab root token: jq -r .root_token .secrets/vault/vault-init.json)"

# ── Data ──────────────────────────────────────────────────────────────────────

data-up: ## (changes state) Start PostgreSQL (generates .secrets/postgres.env once)
	@./scripts/data-up.sh

data-down: ## (changes state) Stop PostgreSQL; its volume is kept
	@./scripts/compose.sh data stop

psql: ## Superuser psql shell in the hospital database
	@podman exec -it srot-postgres psql -U postgres -d "$$(bash -c '. ./scripts/common.sh && srot_conf SROT_DB_NAME')"

db-rotate-root: ## (changes state) Rotate the connection's own password; only Vault knows it afterwards
	@./scripts/db-rotate-root.sh

db-test: ## Issue, use and revoke a dynamic credential; use the static one
	@./scripts/verify.sh database

# ── Terraform ─────────────────────────────────────────────────────────────────

tf-seal: ## (changes state) Apply terraform/vault-seal (vault-s: AppRole for the seal rotator and seal agent)
	@./scripts/tf.sh vault-seal apply

tf-platform: ## (changes state) Apply terraform/vault-platform (AppRole, API policy and identity)
	@./scripts/tf.sh vault-platform apply

tf-database: ## (changes state) Apply terraform/vault-database (mount, connection, roles)
	@./scripts/tf.sh vault-database apply

tf-all: ## (changes state) data-up, then every root in order (vault-seal, vault-platform, vault-database)
	@$(MAKE) --no-print-directory data-up
	@$(MAKE) --no-print-directory tf-seal
	@$(MAKE) --no-print-directory tf-platform
	@$(MAKE) --no-print-directory tf-database

tf-plan-all: ## Plan every root; fails if any has changes
	@for r in vault-seal vault-platform vault-database; do \
		code=0; ./scripts/tf.sh $$r plan >/tmp/srot-plan.$$$$ 2>&1 || code=$$?; \
		case $$code in \
		0) echo "$$r: No changes." ;; \
		2) echo "$$r: CHANGES PENDING" >&2; grep -E '^  [#~+-]|Plan:' /tmp/srot-plan.$$$$ >&2; rm -f /tmp/srot-plan.$$$$; exit 2 ;; \
		*) cat /tmp/srot-plan.$$$$ >&2; rm -f /tmp/srot-plan.$$$$; exit $$code ;; \
		esac; rm -f /tmp/srot-plan.$$$$; \
	done

tf-destroy: ## (changes state) Destroy every root in reverse order; type DESTROY to confirm
	@printf 'This removes the database mount, roles, AppRoles and policies from vault-1 and vault-s. Type DESTROY: '; \
		read answer; [ "$$answer" = DESTROY ] || { echo "Aborted."; exit 1; }
	@./scripts/tf.sh vault-database destroy
	@./scripts/tf.sh vault-platform destroy
	@./scripts/tf.sh vault-seal destroy

# ── App ───────────────────────────────────────────────────────────────────────

rotator-bootstrap: ## (changes state) Deliver both rotators' own credentials (the only ones handed over); idempotent
	@./scripts/rotator-bootstrap.sh

agents-status: ## Both machine identities (seal, API): rotator, secret-id expiry, last rotation, agent token TTL
	@./scripts/agents-status.sh

agents-recover: ## (changes state) Re-deliver a rotator credential that cannot log in; restart rejected agents
	@./scripts/agents-recover.sh

rotate-now: ## (changes state) Rotate a secret-id now: make rotate-now [ROLE=api|seal] (default api)
	@case "$(or $(ROLE),api)" in \
		api) podman exec srot-rotator touch /run/approle/secret-theatre-api/rotate-now ;; \
		seal) podman exec srot-seal-rotator touch /run/approle/seal-autounseal/rotate-now ;; \
		*) echo "ROLE must be api or seal" >&2; exit 64 ;; \
	esac && echo "rotation of $(or $(ROLE),api) requested; watch: make agents-status"

rotation-test: ## (changes state) Self-healing tests: dead token, rotate-now, destroyed secret-id + token, dead rotator credential, revoked seal token
	@./scripts/test-rotation.sh

app-build: ## (changes state) Build the api and web images (TARGETS="api" for one)
	@./scripts/app-build.sh $(TARGETS)

app-up: ## (changes state) Start the rotator, Vault Agent, API and web UI (builds images if missing)
	@./scripts/rotator-bootstrap.sh app
	@podman image exists localhost/srot-api:local && podman image exists localhost/srot-web:local || ./scripts/app-build.sh
	@$(MAKE) --no-print-directory network
	@./scripts/compose.sh app up -d
	@$(MAKE) --no-print-directory open

app-down: ## (changes state) Stop the app stack
	@./scripts/compose.sh app stop

app-rebuild: ## (changes state) Rebuild the images and recreate api and web (after editing app/)
	@./scripts/app-build.sh $(TARGETS)
	@./scripts/compose.sh app up -d --force-recreate api web

open: ## Print the UI address
	@echo "Vault Secret Theatre: http://127.0.0.1:$$(bash -c '. ./scripts/common.sh && srot_conf SROT_PORT_WEB')"

up: ## (changes state) Start everything from a stopped machine: vault (with unseal), data, app
	@$(MAKE) --no-print-directory vault-up
	@$(MAKE) --no-print-directory data-up
	@$(MAKE) --no-print-directory app-up

down: ## (changes state) Stop app, data and vault; containers and volumes are kept
	@./scripts/compose.sh app stop 2>/dev/null || true
	@./scripts/compose.sh data stop 2>/dev/null || true
	@$(MAKE) --no-print-directory vault-down

# ── Tests ─────────────────────────────────────────────────────────────────────

verify: ## End-to-end checks of every section (vault, database, app)
	@./scripts/verify.sh

# ── Maintenance ───────────────────────────────────────────────────────────────

bootstrap: ## (changes state) First run, from zero to verified: certs, Vault, PostgreSQL, Terraform, app. Idempotent
	@$(MAKE) --no-print-directory check
	@$(MAKE) --no-print-directory network
	@$(MAKE) --no-print-directory gen-certs
	@./scripts/vault-bootstrap.sh
	@$(MAKE) --no-print-directory tf-all
	@# Seal plane identity, then move vault-1 from the bootstrap token to the agent's.
	@./scripts/rotator-bootstrap.sh seal
	@./scripts/seal-up.sh
	@$(MAKE) --no-print-directory vault-recreate
	@$(MAKE) --no-print-directory app-up
	@$(MAKE) --no-print-directory verify

doctor: ## Explain what is wrong and which command fixes it (read-only)
	@./scripts/doctor.sh

backup: ## (changes state) Raft snapshots of both nodes, pg_dump, and .secrets into backups/<timestamp>/
	@./scripts/backup.sh

clean-slate: ## (changes state) DESTRUCTIVE: remove containers and volumes, move credentials aside (backup first; type DELETE)
	@./scripts/clean-slate.sh
