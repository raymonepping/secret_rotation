import express from "express";
import { config } from "../config.js";
import { pulseCheck } from "../pulse.js";
import { vault, vaultError } from "../vault.js";

const router = express.Router();

function nowIso() {
  return new Date().toISOString();
}

function addSecondsToNow(seconds) {
  return new Date(Date.now() + seconds * 1000).toISOString();
}

router.post("/issue", async (_req, res) => {
  try {
    const r = await vault(`database/creds/${config.names.dynamicRole}`);
    if (!r.ok) return res.status(r.status).json(vaultError(r));

    return res.json({
      ok: true,
      role: config.names.dynamicRole,
      lease_id: r.data.lease_id,
      lease_duration: r.data.lease_duration,
      renewable: r.data.renewable,
      username: r.data.data.username,
      password: r.data.data.password,
      issued_at: nowIso(),
      expires_at: addSecondsToNow(r.data.lease_duration),
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

router.post("/revoke", async (req, res) => {
  const { lease_id } = req.body;

  if (!lease_id) {
    return res.status(400).json({
      ok: false,
      error: "lease_id is required",
    });
  }

  try {
    const r = await vault("sys/leases/revoke", { method: "PUT", body: { lease_id } });
    if (!r.ok) return res.status(r.status).json(vaultError(r));

    return res.json({
      ok: true,
      lease_id,
      revoked_at: nowIso(),
      status: "flatline",
    });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

export default router;
