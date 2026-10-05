// Lane status → tone (DESIGN.md, "Lane state map"). One meaning per hue.
export function statusTone(status) {
  switch (status) {
    case "stable":
    case "success":
      return "ok";
    case "warning":
    case "rotating":
      return "warn";
    case "critical":
    case "flatline":
    case "failed":
      return "denied";
    default:
      return "idle";
  }
}

export function formatTime(iso) {
  if (!iso) return "n/a";
  return new Date(iso).toLocaleTimeString();
}

export function maskPassword(password) {
  if (!password) return "n/a";
  if (password.length <= 6) return "••••••";
  return `${password.slice(0, 2)}••••••${password.slice(-2)}`;
}

export function shortenLeaseId(leaseId) {
  if (!leaseId) return "n/a";
  if (leaseId.length <= 42) return leaseId;
  return `${leaseId.slice(0, 24)}…${leaseId.slice(-12)}`;
}

// The Error a lane throws when the API refused: it carries Vault's status and
// its error text, verbatim, for Verdict.
export function apiError(response, data, fallback) {
  const error = new Error(
    (typeof data?.error === "string" ? data.error : data?.error?.message) || fallback,
  );
  error.vaultStatus = data?.vault_status ?? response.status;
  return error;
}
