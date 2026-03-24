import { useEffect, useState } from "react";

const API_BASE = import.meta.env.VITE_API_BASE || "http://127.0.0.1:3000";

function formatTime(iso) {
  if (!iso) return "n/a";
  return new Date(iso).toLocaleTimeString();
}

function maskPassword(password) {
  if (!password) return "n/a";
  if (password.length <= 6) return "••••••";
  return `${password.slice(0, 2)}••••••${password.slice(-2)}`;
}

function computeStatus(ttl, currentStatus) {
  if (currentStatus === "rotating") return "rotating";
  if (currentStatus === "failed") return "failed";
  if (ttl <= 10) return "critical";
  if (ttl <= 30) return "warning";
  return "stable";
}

export default function SurgeonCard({ autoMode, addSharedEvent }) {
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
        throw new Error(data.error || "Failed to load surgeon credentials");
      }

      setState((prev) => ({
        ...prev,
        status: computeStatus(data.ttl, "stable"),
        username: data.username,
        password: data.password,
        ttl: data.ttl,
        rotationPeriod: data.rotation_period,
        rotatesAt: data.rotates_at,
        lastRotation: data.last_vault_rotation || prev.lastRotation,
      }));
    } catch (_err) {
      setState((prev) => ({
        ...prev,
        status: "failed",
      }));
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
    } catch (_err) {
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
        throw new Error(data.error || "Rotation failed");
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
    } catch (_err) {
      setState((prev) => ({
        ...prev,
        status: "failed",
      }));

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

  return (
    <section className={`card lane-card status-${state.status}`}>
      <div className="lane-card-inner">
        <div className="lane-card-left">
          <div className="panel-header lane-header">
            <div>
              <p className="panel-label">Lane</p>
              <h2>Surgeon</h2>
            </div>
          </div>

          <div className="lane-stats lane-stats-wide">
            <div className="lane-stat">
              <span className="label">Username</span>
              <span className="value">{state.username || "n/a"}</span>
            </div>

            <div className="lane-stat">
              <span className="label">Password</span>
              <span className="value">{maskPassword(state.password)}</span>
            </div>

            <div className={`lane-stat severity severity-${computeStatus(state.ttl, state.status)}`}>
              <span className="label">Next Rotation</span>
              <span className="value">{state.ttl ? `${state.ttl}s` : "n/a"}</span>
            </div>

            <div className="lane-stat">
              <span className="label">Rotation Period</span>
              <span className="value">
                {state.rotationPeriod ? `${state.rotationPeriod}s` : "n/a"}
              </span>
            </div>

            <div className="lane-stat">
              <span className="label">Last Rotation</span>
              <span className="value">{formatTime(state.lastRotation)}</span>
            </div>

            <div className="lane-stat">
              <span className="label">Last Test</span>
              <span className="value">{state.lastTest}</span>
            </div>
          </div>
        </div>

        <div className="lane-card-right">
          <div className={`status-pill status-${state.status}`}>
            {state.status.toUpperCase()}
          </div>

          <div className="doctor-actions">
            <button onClick={loadCreds} className="secondary">
              Load Static Creds
            </button>
            <button onClick={testCreds} className="secondary" disabled={!state.username}>
              Test
            </button>
            <button onClick={rotateNow} disabled={!state.username || state.status === "rotating"}>
              {state.status === "rotating" ? "Rotating..." : "Rotate Role"}
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}