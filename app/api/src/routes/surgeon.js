import express from "express";
import pg from "pg";

const router = express.Router();
const { Client } = pg;

const VAULT_ADDR = process.env.VAULT_ADDR || "http://127.0.0.1:8200";
const VAULT_TOKEN = process.env.VAULT_TOKEN;

function nowIso() {
  return new Date().toISOString();
}

function addSeconds(seconds) {
  const value = Number(seconds);

  if (!Number.isFinite(value) || value < 0) {
    return null;
  }

  return new Date(Date.now() + value * 1000).toISOString();
}

router.post("/issue", async (_req, res) => {
  try {
    const response = await fetch(
      `${VAULT_ADDR}/v1/database/static-creds/surgeon`,
      {
        method: "GET",
        headers: {
          "X-Vault-Token": VAULT_TOKEN,
        },
      },
    );

    const payload = await response.json();

    if (!response.ok) {
      return res.status(response.status).json({
        ok: false,
        error: payload,
      });
    }

    const ttl = Number(payload.data?.ttl || 0);
    const rotationPeriod = Number(payload.data?.rotation_period || 0);
    const lastVaultRotation = payload.data?.last_vault_rotation || null;

    return res.json({
      ok: true,
      role: "surgeon",
      username: payload.data?.username || "",
      password: payload.data?.password || "",
      ttl,
      rotation_period: rotationPeriod,
      issued_at: nowIso(),
      rotates_at: ttl > 0 ? addSeconds(ttl) : null,
      last_vault_rotation: lastVaultRotation,
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

router.post("/rotate", async (_req, res) => {
  try {
    const response = await fetch(
      `${VAULT_ADDR}/v1/database/rotate-role/surgeon`,
      {
        method: "POST",
        headers: {
          "X-Vault-Token": VAULT_TOKEN,
        },
      },
    );

    const text = await response.text();

    if (!response.ok) {
      return res.status(response.status).json({
        ok: false,
        error: text,
      });
    }

    return res.json({
      ok: true,
      rotated_at: nowIso(),
      message: "Static role rotated",
    });
  } catch (error) {
    return res.status(500).json({
      ok: false,
      error: error.message,
    });
  }
});

export default router;
