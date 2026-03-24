import express from "express";

const router = express.Router();

const VAULT_ADDR = process.env.VAULT_ADDR || "http://127.0.0.1:8200";
const VAULT_TOKEN = process.env.VAULT_TOKEN;

function nowIso() {
  return new Date().toISOString();
}

router.post("/rotate-root", async (_req, res) => {
  try {
    const response = await fetch(
      `${VAULT_ADDR}/v1/database/rotate-root/library-postgres`,
      {
        method: "POST",
        headers: {
          "X-Vault-Token": VAULT_TOKEN,
        },
      }
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
      message: "Database root credential rotated",
    });
  } catch (error) {
    return res.status(500).json({
      ok: false,
      error: error.message,
    });
  }
});

export default router;