import { useEffect, useState } from "react";
import { API_BASE } from "../api";
import { apiError, formatTime, maskPassword, statusTone } from "../lib/format";
import KeyValue from "../ui/KeyValue";
import Pane from "../ui/Pane";
import StatusPill from "../ui/StatusPill";
import TtlBar from "../ui/TtlBar";
import Verdict from "../ui/Verdict";

function computeStatus(ttl, currentStatus) {
  if (currentStatus === "rotating") return "rotating";
  if (currentStatus === "failed") return "failed";
  if (ttl <= 10) return "critical";
  if (ttl <= 30) return "warning";
  return "stable";
}

export default function SurgeonCard({ autoMode, addSharedEvent, role }) {
  const [state, setState] = useState({
    status: "idle",
    username: "",
    password: "",
    ttl: 0,
    rotationPeriod: 0,
    rotatesAt: "",
    lastRotation: null,
    lastTest: "n/a",
  });
  const [failure, setFailure] = useState(null);

  useEffect(() => {
    if (!state.rotatesAt || state.status === "idle") return;

    const timer = setInterval(() => {
      const seconds = Math.max(
        0,
        Math.floor((new Date(state.rotatesAt).getTime() - Date.now()) / 1000)
      );

      setState((prev) => ({
        ...prev,
        ttl: seconds,
        status: computeStatus(seconds, prev.status),
      }));
    }, 500);

    return () => clearInterval(timer);
  }, [state.rotatesAt, state.status]);

  async function loadCreds() {
    try {
      const res = await fetch(`${API_BASE}/api/surgeon/issue`, {
        method: "POST",
      });

      const data = await res.json();

      if (!res.ok || !data.ok) {
        throw apiError(res, data, "Failed to load surgeon credentials");
      }

      setFailure(null);
      setState((prev) => ({
        ...prev,
        status: computeStatus(data.ttl, "stable"),
        username: data.username,
        password: data.password,
        ttl: data.ttl,
        rotationPeriod: data.rotation_period,
        // On this browser's clock (see PatientMonitor): ttl is relative.
        rotatesAt: data.ttl > 0 ? new Date(Date.now() + data.ttl * 1000).toISOString() : null,
        lastRotation: data.last_vault_rotation || prev.lastRotation,
      }));
    } catch (error) {
      setState((prev) => ({
        ...prev,
        status: "failed",
      }));
      setFailure({ title: "Read the static credential", path: `database/static-creds/${role}`, error: error.message, vaultStatus: error.vaultStatus });
    }
  }

  async function testCreds() {
    try {
      const res = await fetch(`${API_BASE}/api/surgeon/test`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          username: state.username,
          password: state.password,
        }),
      });

      const data = await res.json();

      if (!res.ok || !data.ok) {
        throw new Error(data.error || "Test failed");
      }

      setState((prev) => ({
        ...prev,
        lastTest: "alive",
      }));
    } catch {
      setState((prev) => ({
        ...prev,
        lastTest: "failed",
        status: "critical",
      }));
    }
  }

  async function rotateNow() {
    setState((prev) => ({
      ...prev,
      status: "rotating",
    }));

    try {
      const res = await fetch(`${API_BASE}/api/surgeon/rotate`, {
        method: "POST",
      });

      const data = await res.json();

      if (!res.ok || !data.ok) {
        throw apiError(res, data, "Rotation failed");
      }

      addSharedEvent("Surgeon rotated static role password", "warning", "surgeon");

      await loadCreds();

      setState((prev) => ({
        ...prev,
        status: "success",
        lastRotation: data.rotated_at,
      }));

      setTimeout(() => {
        setState((prev) => ({
          ...prev,
          status: computeStatus(prev.ttl, "stable"),
        }));
      }, 1200);
    } catch (error) {
      setState((prev) => ({
        ...prev,
        status: "failed",
      }));
      setFailure({ title: "Rotate the static role", path: `database/rotate-role/${role}`, error: error.message, vaultStatus: error.vaultStatus });

      addSharedEvent("Surgeon failed to rotate static role password", "critical", "surgeon");
    }
  }

  useEffect(() => {
    if (!autoMode) return;
    if (!state.username) {
      loadCreds();
      return;
    }

    const interval = setInterval(() => {
      rotateNow();
    }, 50000);

    return () => clearInterval(interval);
  }, [autoMode, state.username]);

  const tone = statusTone(state.status);
  const ttlTone = statusTone(computeStatus(state.ttl, state.status));

  return (
    <Pane
      id="surgeon"
      eyebrow="Static role · rotate-role"
      title="Surgeon"
      tone={tone === "warn" || tone === "denied" ? tone : undefined}
      aside={<StatusPill status={state.status} live={state.status === "rotating"} />}
    >
      <div className="lane-body">
        <div className="lane-row">
          <div className="lane-body">
            <p className="lede">
              The account exists in PostgreSQL; Vault owns its password and changes it on a schedule, or now.
            </p>
            <div className="kv-grid">
              <KeyValue label="Username" value={state.username || "n/a"} tone="authority" mono />
              <KeyValue label="Password" value={maskPassword(state.password)} tone="cipher" />
              <KeyValue label="Rotation period" value={state.rotationPeriod ? `${state.rotationPeriod}s` : "n/a"} />
              <KeyValue label="Last rotation" value={formatTime(state.lastRotation)} />
              <KeyValue
                label="Last test"
                value={state.lastTest}
                tone={state.lastTest === "alive" ? "ok" : state.lastTest === "failed" ? "denied" : undefined}
              />
            </div>
          </div>
          <div className="lane-actions">
            <button type="button" onClick={loadCreds} className="btn btn-quiet">
              Load static creds
            </button>
            <button type="button" onClick={testCreds} className="btn btn-quiet" disabled={!state.username}>
              Test
            </button>
            <button
              type="button"
              onClick={rotateNow}
              className="btn btn-amber"
              disabled={!state.username || state.status === "rotating"}
            >
              {state.status === "rotating" ? "Rotating…" : "Rotate role"}
            </button>
          </div>
        </div>
        <TtlBar label="Next rotation" seconds={state.ttl} total={state.rotationPeriod} tone={state.username ? ttlTone : "idle"} />
        {failure && <Verdict {...failure} sentence="Vault did not complete this request." />}
      </div>
    </Pane>
  );
}
