import { useEffect, useState } from "react";

const API_BASE = import.meta.env.VITE_API_BASE || "http://127.0.0.1:3000";

function normalizeStatus(status) {
  return status === "idle" ? "stable" : status;
}

export default function DoctorCard({ autoMode, addSharedEvent }) {
  const [state, setState] = useState({
    status: "stable",
    lastRotation: null,
  });

  async function rotateRoot() {
    setState((prev) => ({ ...prev, status: "rotating" }));

    try {
      const res = await fetch(`${API_BASE}/api/doctor/rotate-root`, {
        method: "POST",
      });

      const data = await res.json();

      if (!res.ok || !data.ok) {
        throw new Error(data.error || "Rotation failed");
      }

      setState({
        status: "success",
        lastRotation: data.rotated_at,
      });

      addSharedEvent("Doctor rotated database root credential", "success", "doctor");

      setTimeout(() => {
        setState((prev) => ({
          ...prev,
          status: "stable",
        }));
      }, 1400);
    } catch (_err) {
      setState((prev) => ({
        ...prev,
        status: "failed",
      }));

      addSharedEvent("Doctor failed to rotate database root credential", "critical", "doctor");
    }
  }

  useEffect(() => {
    if (!autoMode) return;

    const interval = setInterval(() => {
      rotateRoot();
    }, 45000);

    return () => clearInterval(interval);
  }, [autoMode]);

  const displayStatus = normalizeStatus(state.status);

  return (
    <section className={`card lane-card status-${displayStatus}`}>
      <div className="lane-card-inner">
        <div className="lane-card-left">
          <div className="panel-header lane-header">
            <div>
              <p className="panel-label">Lane</p>
              <h2>Doctor</h2>
            </div>
          </div>

          <div className="lane-stats">
            <div className="lane-stat">
              <span className="label">Last Rotation</span>
              <span className="value">
                {state.lastRotation
                  ? new Date(state.lastRotation).toLocaleTimeString()
                  : "n/a"}
              </span>
            </div>

            <div className="lane-stat">
              <span className="label">Connection</span>
              <span className="value">library-postgres</span>
            </div>
          </div>
        </div>

        <div className="lane-card-right">
          <div className={`status-pill status-${displayStatus}`}>
            {displayStatus.toUpperCase()}
          </div>

          <button
            onClick={rotateRoot}
            className="doctor-button"
            disabled={state.status === "rotating"}
          >
            {state.status === "rotating" ? "Rotating..." : "Rotate DB Root"}
          </button>
        </div>
      </div>
    </section>
  );
}