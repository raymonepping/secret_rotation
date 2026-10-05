import express from "express";
import { config } from "../config.js";
import { vault, vaultError } from "../vault.js";

const router = express.Router();

function nowIso() {
  return new Date().toISOString();
}

router.post("/rotate-root", async (_req, res) => {
  try {
    const r = await vault(`database/rotate-root/${config.names.connection}`, { method: "POST" });
    if (!r.ok) return res.status(r.status).json(vaultError(r));

    return res.json({
      ok: true,
      connection: config.names.connection,
      rotated_at: nowIso(),
      message: "Database root credential rotated",
    });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

export default router;
