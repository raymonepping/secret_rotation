import { useEffect, useState } from "react";
import { API_BASE } from "../api";
import { apiError, formatTime, statusTone } from "../lib/format";
import KeyValue from "../ui/KeyValue";
import Pane from "../ui/Pane";
import StatusPill from "../ui/StatusPill";
import Verdict from "../ui/Verdict";

function normalizeStatus(status) {
  return status === "idle" ? "stable" : status;
}

export default function DoctorCard({ autoMode, addSharedEvent, connection }) {
  const [state, setState] = useState({
    status: "stable",
    lastRotation: null,
  });
  const [failure, setFailure] = useState(null);

  async function rotateRoot() {
    setState((prev) => ({ ...prev, status: "rotating" }));

    try {
      const res = await fetch(`${API_BASE}/api/doctor/rotate-root`, {
        method: "POST",
      });

      const data = await res.json();

      if (!res.ok || !data.ok) {
        throw apiError(res, data, "Rotation failed");
      }

      setFailure(null);
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
    } catch (error) {
      setState((prev) => ({
        ...prev,
        status: "failed",
      }));
      setFailure({ title: "Rotate the root credential", path: `database/rotate-root/${connection}`, error: error.message, vaultStatus: error.vaultStatus });

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
  const tone = statusTone(displayStatus);

  return (
    <Pane
      id="doctor"
      eyebrow="Root credential · rotate-root"
      title="Doctor"
      tone={tone === "warn" || tone === "denied" ? tone : undefined}
      aside={<StatusPill status={displayStatus} live={state.status === "rotating"} />}
    >
      <div className="lane-body">
        <div className="lane-row">
          <div className="lane-body">
            <p className="lede">
              Vault changes the password of its own database account. Afterwards only Vault knows it, and
              every lane keeps working.
            </p>
            <div className="kv-grid">
              <KeyValue label="Connection" value={connection} tone="authority" mono />
              <KeyValue label="Last rotation" value={formatTime(state.lastRotation)} tone={state.lastRotation ? "ok" : undefined} />
            </div>
          </div>
          <div className="lane-actions">
            <button type="button" onClick={rotateRoot} className="btn btn-amber" disabled={state.status === "rotating"}>
              {state.status === "rotating" ? "Rotating…" : "Rotate DB root"}
            </button>
          </div>
        </div>
        {failure && <Verdict {...failure} sentence="Vault did not rotate the root credential." />}
      </div>
    </Pane>
  );
}
