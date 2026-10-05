// Runtime configuration, from the environment. Defaults match
// config/defaults.env so `npm run dev` against the Podman stack works too.
const env = process.env;

export const config = {
  port: Number(env.PORT || 3000),

  vaultAddr: env.VAULT_ADDR || "https://127.0.0.1:18200",
  vaultSealAddr: env.VAULT_SEAL_ADDR || "https://127.0.0.1:18190",
  // Written and kept fresh by the Vault Agent. Never a token in the env.
  vaultTokenFile: env.VAULT_TOKEN_FILE || "/run/vault/token",

  pg: {
    host: env.PGHOST || "127.0.0.1",
    port: Number(env.PGPORT || 15432),
    database: env.PGDATABASE || "hospital",
  },

  names: {
    connection: env.DB_CONNECTION || "hospital-postgres",
    dynamicRole: env.DB_ROLE_DYNAMIC || "patient-readonly",
    staticRole: env.DB_ROLE_STATIC || "surgeon",
  },

  // Only `npm run dev` in app/web needs CORS; in the stack nginx serves the
  // UI and the API from one origin.
  corsOrigins: (env.CORS_ORIGINS || "http://127.0.0.1:5173,http://localhost:5173")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean),
};
