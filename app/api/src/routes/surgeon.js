import express from "express";
import { config } from "../config.js";
import { pulseCheck } from "../pulse.js";
import { vault, vaultError } from "../vault.js";

const router = express.Router();

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
    const r = await vault(`database/static-creds/${config.names.staticRole}`);
    if (!r.ok) return res.status(r.status).json(vaultError(r));

    const ttl = Number(r.data.data?.ttl || 0);
    const rotationPeriod = Number(r.data.data?.rotation_period || 0);

    return res.json({
      ok: true,
      role: config.names.staticRole,
      username: r.data.data?.username || "",
      password: r.data.data?.password || "",
      ttl,
      rotation_period: rotationPeriod,
      issued_at: nowIso(),
      rotates_at: ttl > 0 ? addSeconds(ttl) : null,
      last_vault_rotation: r.data.data?.last_vault_rotation || null,
      status: "stable",
    });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
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

  const pulse = await pulseCheck(username, password);
  return res.status(pulse.ok ? 200 : 401).json({ ...pulse, checked_at: nowIso() });
});

router.post("/rotate", async (_req, res) => {
  try {
    const r = await vault(`database/rotate-role/${config.names.staticRole}`, { method: "POST" });
    if (!r.ok) return res.status(r.status).json(vaultError(r));

    return res.json({
      ok: true,
      rotated_at: nowIso(),
      message: "Static role rotated",
    });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

export default router;
