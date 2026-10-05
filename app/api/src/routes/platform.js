import net from "node:net";
import express from "express";
import { config } from "../config.js";
import { vault } from "../vault.js";

const router = express.Router();

// sys/health answers without a token. These query flags make every state
// return 200, so the body (not the status code) carries the answer.
const HEALTH = "sys/health?standbyok=true&perfstandbyok=true&sealedcode=200&uninitcode=200&drsecondarycode=200";

async function nodeHealth(base) {
  try {
    const r = await vault(HEALTH, { auth: false, base });
    if (!r.data || r.data.errors) return { reachable: false, error: r.data?.errors?.join("; ") };
    return {
      reachable: true,
      initialized: r.data.initialized,
      sealed: r.data.sealed,
      standby: r.data.standby,
      version: r.data.version,
    };
  } catch (error) {
    return { reachable: false, error: error.cause?.code || error.message };
  }
}

function tcpReachable(host, port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port, timeout: 2000 });
    const done = (ok) => {
      socket.destroy();
      resolve(ok);
    };
    socket.once("connect", () => done(true));
    socket.once("timeout", () => done(false));
    socket.once("error", () => done(false));
  });
}

// What the API's own identity looks like: the token's TTL and policies,
// never the token.
async function agentIdentity() {
  try {
    const r = await vault("auth/token/lookup-self");
    if (!r.ok) return { valid: false, error: r.data?.errors?.join("; ") };
    return {
      valid: true,
      display_name: r.data.data.display_name,
      policies: r.data.data.policies,
      ttl: r.data.data.ttl,
    };
  } catch (error) {
    return { valid: false, error: error.message };
  }
}

router.get("/", async (_req, res) => {
  const [seal, primary, postgres, identity] = await Promise.all([
    nodeHealth(config.vaultSealAddr),
    nodeHealth(config.vaultAddr),
    tcpReachable(config.pg.host, config.pg.port),
    agentIdentity(),
  ]);

  res.json({
    checked_at: new Date().toISOString(),
    seal,
    vault: primary,
    postgres: { reachable: postgres, host: config.pg.host, database: config.pg.database },
    identity,
    names: config.names,
  });
});

export default router;
