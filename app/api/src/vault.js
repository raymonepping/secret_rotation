import { readFile } from "node:fs/promises";
import { config } from "./config.js";

// The Vault Agent re-authenticates and rewrites the token file on its own
// schedule, so the file is read on every call instead of once at start.
export async function readToken() {
  try {
    const token = (await readFile(config.vaultTokenFile, "utf8")).trim();
    return token || null;
  } catch {
    return null;
  }
}

// vault("database/creds/x") → { ok, status, data }. Vault's own error text is
// kept verbatim so the UI can show what Vault actually said.
export async function vault(path, { method = "GET", body, auth = true, base = config.vaultAddr } = {}) {
  const headers = {};
  if (auth) {
    const token = await readToken();
    if (!token) {
      return { ok: false, status: 503, data: { errors: ["no Vault token yet: the Vault Agent has not written its sink"] } };
    }
    headers["X-Vault-Token"] = token;
  }
  if (body !== undefined) headers["Content-Type"] = "application/json";

  const res = await fetch(`${base}/v1/${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(5000),
  });
  const text = await res.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { errors: [text] };
    }
  }
  return { ok: res.ok, status: res.status, data };
}

// The error body every route returns when Vault refused.
export function vaultError(result) {
  return {
    ok: false,
    vault_status: result.status,
    error: result.data?.errors?.join("; ") || `Vault answered ${result.status}`,
  };
}
