import express from "express";
import pg from "pg";

const router = express.Router();
const { Client } = pg;

const VAULT_ADDR = process.env.VAULT_ADDR || "http://127.0.0.1:8200";
const VAULT_TOKEN = process.env.VAULT_TOKEN;

function nowIso() {
  return new Date().toISOString();
}

function addSecondsToNow(seconds) {
  return new Date(Date.now() + seconds * 1000).toISOString();
}

router.post("/issue", async (_req, res) => {
  try {
    const response = await fetch(`${VAULT_ADDR}/v1/database/creds/patient-readonly`, {
      method: "GET",
      headers: {
        "X-Vault-Token": VAULT_TOKEN,
      },
    });

    const payload = await response.json();

    if (!response.ok) {
      return res.status(response.status).json({
        ok: false,
        error: payload,
      });
    }

    return res.json({
      ok: true,
      role: "patient-readonly",
      lease_id: payload.lease_id,
      lease_duration: payload.lease_duration,
      renewable: payload.renewable,
      username: payload.data.username,
      password: payload.data.password,
      issued_at: nowIso(),
      expires_at: addSecondsToNow(payload.lease_duration),
      status: "stable",
    });
  } catch (error) {
    return res.status(500).json({
      ok: false,
      error: error.message,
    });
  }
});

router.post("/test", async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({
      ok: false,
      error: "username and password are required",
    });
  }

  const client = new Client({
    host: process.env.PGHOST || "127.0.0.1",
    port: Number(process.env.PGPORT || 5432),
    database: process.env.PGDATABASE || "librarydemo",
    user: username,
    password,
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

    return res.json({
      ok: true,
      checked_at: nowIso(),
      result: result.rows[0],
    });
  } catch (error) {
    return res.status(401).json({
      ok: false,
      checked_at: nowIso(),
      error: error.message,
    });
  } finally {
    await client.end().catch(() => {});
  }
});

router.post("/revoke", async (req, res) => {
  const { lease_id } = req.body;

  if (!lease_id) {
    return res.status(400).json({
      ok: false,
      error: "lease_id is required",
    });
  }

  try {
    const response = await fetch(`${VAULT_ADDR}/v1/sys/leases/revoke`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        "X-Vault-Token": VAULT_TOKEN,
      },
      body: JSON.stringify({ lease_id }),
    });

    const text = await response.text();

    if (!response.ok) {
      return res.status(response.status).json({
        ok: false,
        error: text,
      });
    }

    return res.json({
      ok: true,
      lease_id,
      revoked_at: nowIso(),
      status: "flatline",
    });
  } catch (error) {
    return res.status(500).json({
      ok: false,
      error: error.message,
    });
  }
});

export default router;