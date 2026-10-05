import pg from "pg";
import { config } from "./config.js";

const { Client } = pg;

// Log in to PostgreSQL with a credential Vault issued and read the demo table:
// the proof that the credential is alive right now.
export async function pulseCheck(username, password) {
  const client = new Client({
    ...config.pg,
    user: username,
    password,
    connectionTimeoutMillis: 3000,
  });

  try {
    await client.connect();
    const result = await client.query(`
      SELECT
        current_user,
        now(),
        count(*)::int AS rows
      FROM patient_status_demo
    `);
    return { ok: true, result: result.rows[0] };
  } catch (error) {
    return { ok: false, error: error.message };
  } finally {
    await client.end().catch(() => {});
  }
}
