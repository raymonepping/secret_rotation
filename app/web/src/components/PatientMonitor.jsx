import { useEffect, useMemo, useRef, useState } from "react";

const API_BASE = import.meta.env.VITE_API_BASE || "http://127.0.0.1:3000";

const initialState = {
  role: "patient-readonly",
  leaseId: "",
  username: "",
  password: "",
  leaseDuration: 0,
  issuedAt: "",
  expiresAt: "",
  secondsRemaining: 0,
  status: "idle",
  testResult: null,
};

function nowTs() {
  return new Date().toISOString();
}

function formatTime(iso) {
  if (!iso) return "n/a";
  return new Date(iso).toLocaleTimeString();
}

function maskPassword(password) {
  if (!password) return "n/a";
  if (password.length <= 6) return "••••••";
  return `${password.slice(0, 2)}••••••${password.slice(-2)}`;
}

function shortenLeaseId(leaseId) {
  if (!leaseId) return "n/a";
  if (leaseId.length <= 42) return leaseId;
  return `${leaseId.slice(0, 24)}...${leaseId.slice(-12)}`;
}

function computeStatus(secondsRemaining, currentStatus) {
  if (currentStatus === "flatline") return "flatline";
  if (secondsRemaining <= 0) return "flatline";
  if (secondsRemaining <= 10) return "critical";
  if (secondsRemaining <= 30) return "warning";
  return "stable";
}

export default function PatientMonitor({ autoMode, sharedEvents, addSharedEvent }) {
  const [patient, setPatient] = useState(initialState);
  const [localEvents, setLocalEvents] = useState([]);
  const [busy, setBusy] = useState({
    issue: false,
    test: false,
    revoke: false,
  });

  const warned30Ref = useRef(false);
  const warned10Ref = useRef(false);
  const expiryLoggedRef = useRef(false);
  const autoTestingRef = useRef(false);
  const autoIssuedOnceRef = useRef(false);

  function addLocalEvent(message, level = "info") {
    setLocalEvents((prev) => [
      {
        id: crypto.randomUUID(),
        ts: nowTs(),
        message,
        level,
        source: "patient",
      },
      ...prev,
    ]);
  }

  function addEvent(message, level = "info", source = "patient") {
    addLocalEvent(message, level);
    if (source !== "patient") {
      addSharedEvent(message, level, source);
    }
  }

  function resetThresholdRefs() {
    warned30Ref.current = false;
    warned10Ref.current = false;
    expiryLoggedRef.current = false;
  }

  async function performPulseCheck({ silent = false } = {}) {
    if (!patient.username || !patient.password) return;
    if (autoTestingRef.current) return;

    autoTestingRef.current = true;

    try {
      const response = await fetch(`${API_BASE}/api/patient/test`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          username: patient.username,
          password: patient.password,
        }),
      });

      const data = await response.json();

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Pulse check failed");
      }

      setPatient((prev) => ({
        ...prev,
        testResult: data,
      }));

      if (!silent) {
        addLocalEvent("Pulse confirmed via PostgreSQL", "success");
      }
    } catch (error) {
      setPatient((prev) => ({
        ...prev,
        status: "flatline",
        secondsRemaining: 0,
        testResult: {
          ok: false,
          error: error.message,
        },
      }));

      addLocalEvent(`Pulse lost: ${error.message}`, "critical");
    } finally {
      autoTestingRef.current = false;
    }
  }

  async function handleIssue() {
    setBusy((prev) => ({ ...prev, issue: true }));

    try {
      const response = await fetch(`${API_BASE}/api/patient/issue`, {
        method: "POST",
      });

      const data = await response.json();

      if (!response.ok || !data.ok) {
        throw new Error(data.error?.message || data.error || "Failed to issue secret");
      }

      const secondsRemaining = Math.max(
        0,
        Math.floor((new Date(data.expires_at).getTime() - Date.now()) / 1000)
      );

      resetThresholdRefs();

      setPatient({
        role: data.role,
        leaseId: data.lease_id,
        username: data.username,
        password: data.password,
        leaseDuration: data.lease_duration,
        issuedAt: data.issued_at,
        expiresAt: data.expires_at,
        secondsRemaining,
        status: "stable",
        testResult: null,
      });

      addLocalEvent(`Patient admitted. Lease issued for ${data.username}`, "success");

      setTimeout(() => {
        performPulseCheck({ silent: false });
      }, 250);
    } catch (error) {
      addLocalEvent(`Issue failed: ${error.message}`, "critical");
    } finally {
      setBusy((prev) => ({ ...prev, issue: false }));
    }
  }

  async function handleTest() {
    if (!patient.username || !patient.password) {
      addLocalEvent("No active patient secret to test", "warning");
      return;
    }

    setBusy((prev) => ({ ...prev, test: true }));

    try {
      await performPulseCheck({ silent: false });
    } finally {
      setBusy((prev) => ({ ...prev, test: false }));
    }
  }

  async function handleRevoke() {
    if (!patient.leaseId) {
      addLocalEvent("No lease to revoke", "warning");
      return;
    }

    setBusy((prev) => ({ ...prev, revoke: true }));

    try {
      const response = await fetch(`${API_BASE}/api/patient/revoke`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          lease_id: patient.leaseId,
        }),
      });

      const data = await response.json();

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Revoke failed");
      }

      setPatient((prev) => ({
        ...prev,
        status: "flatline",
        secondsRemaining: 0,
      }));

      addLocalEvent("Lease revoked. Flatline detected", "critical");
    } catch (error) {
      addLocalEvent(`Revoke failed: ${error.message}`, "critical");
    } finally {
      setBusy((prev) => ({ ...prev, revoke: false }));
    }
  }

  useEffect(() => {
    if (!patient.expiresAt || patient.status === "flatline") return;

    const timer = setInterval(() => {
      const secondsRemaining = Math.max(
        0,
        Math.floor((new Date(patient.expiresAt).getTime() - Date.now()) / 1000)
      );

      setPatient((prev) => {
        const nextStatus = computeStatus(secondsRemaining, prev.status);
        return {
          ...prev,
          secondsRemaining,
          status: nextStatus,
        };
      });
    }, 500);

    return () => clearInterval(timer);
  }, [patient.expiresAt, patient.status]);

  useEffect(() => {
    if (patient.status === "idle") return;

    if (patient.secondsRemaining <= 30 && patient.secondsRemaining > 10 && !warned30Ref.current) {
      warned30Ref.current = true;
      addLocalEvent("Lease entering warning zone", "warning");
    }

    if (patient.secondsRemaining <= 10 && patient.secondsRemaining > 0 && !warned10Ref.current) {
      warned10Ref.current = true;
      addLocalEvent("Patient critical", "critical");
    }

    if (patient.secondsRemaining === 0 && patient.status === "flatline" && !expiryLoggedRef.current) {
      expiryLoggedRef.current = true;
      addLocalEvent("Lease expired. Flatline detected", "critical");
      performPulseCheck({ silent: true });
    }
  }, [patient.secondsRemaining, patient.status]);

  useEffect(() => {
    if (!patient.username || !patient.password) return;
    if (patient.status === "flatline" || patient.status === "idle") return;

    const interval = setInterval(() => {
      performPulseCheck({ silent: true });
    }, 5000);

    return () => clearInterval(interval);
  }, [patient.username, patient.password, patient.status]);

  useEffect(() => {
    if (!autoMode) {
      autoIssuedOnceRef.current = false;
      return;
    }

    if (patient.status === "idle" && !autoIssuedOnceRef.current) {
      autoIssuedOnceRef.current = true;
      handleIssue();
    }
  }, [autoMode, patient.status]);

  useEffect(() => {
    if (!autoMode) return;
    if (patient.status === "flatline") {
      const timeout = setTimeout(() => {
        handleIssue();
      }, 1200);
      return () => clearTimeout(timeout);
    }
  }, [autoMode, patient.status]);

  const mergedEvents = useMemo(() => {
    return [...sharedEvents, ...localEvents]
      .sort((a, b) => new Date(b.ts).getTime() - new Date(a.ts).getTime())
      .slice(0, 12);
  }, [sharedEvents, localEvents]);

  const statusClass = useMemo(() => `status-${patient.status}`, [patient.status]);

  const waveformClass = useMemo(() => {
    return `waveform ${statusClass} ${patient.status !== "flatline" ? "pulse" : "flat"}`;
  }, [statusClass, patient.status]);

  const statusTitle = useMemo(() => {
    switch (patient.status) {
      case "stable":
        return "STABLE";
      case "warning":
        return "WARNING";
      case "critical":
        return "CRITICAL";
      case "flatline":
        return "FLATLINE";
      default:
        return "IDLE";
    }
  }, [patient.status]);

  return (
    <div className="dashboard-grid">
      <section className={`monitor-panel card ${statusClass}`}>
        <div className="panel-header">
          <div>
            <p className="panel-label">Lane</p>
            <h2>Patient</h2>
          </div>
          <div className={`status-pill ${statusClass}`}>
            {patient.status.toUpperCase()}
          </div>
        </div>

        <div className={`monitor-screen ${statusClass}`}>
          <div className="screen-sweep" />

          <div className={waveformClass}>
            <svg viewBox="0 0 1200 220" preserveAspectRatio="none">
              <polyline
                points={
                  patient.status === "flatline"
                    ? "0,110 1200,110"
                    : "0,110 110,110 160,108 190,111 220,110 260,112 320,110 360,110 400,110 430,60 455,140 485,85 515,110 620,110 700,110 760,108 810,111 860,110 900,112 950,110 980,110 1010,70 1035,145 1065,88 1095,110 1200,110"
                }
              />
            </svg>
          </div>

          <div className={`state-overlay ${statusClass}`}>{statusTitle}</div>

          <div className="monitor-overlay">
            <div className="metric">
              <span className="metric-label">Seconds Left</span>
              <span className="metric-value">{patient.secondsRemaining}</span>
            </div>
            <div className="metric">
              <span className="metric-label">Lease</span>
              <span className="metric-value small" title={patient.leaseId || "n/a"}>
                {shortenLeaseId(patient.leaseId)}
              </span>
            </div>
          </div>
        </div>

        <div className="button-row">
          <button onClick={handleIssue} disabled={busy.issue}>
            {busy.issue ? "Issuing..." : "Issue Secret"}
          </button>
          <button
            onClick={handleTest}
            disabled={busy.test || !patient.username || patient.status === "idle"}
            className="secondary"
          >
            {busy.test ? "Testing..." : "Test Pulse"}
          </button>
          <button
            onClick={handleRevoke}
            disabled={busy.revoke || !patient.leaseId || patient.status === "flatline"}
            className="danger"
          >
            {busy.revoke ? "Revoking..." : "Revoke"}
          </button>
        </div>
      </section>

      <aside className="side-column">
        <section className="card">
          <div className="panel-header compact">
            <div>
              <p className="panel-label">Vitals</p>
              <h3>Current Secret</h3>
            </div>
          </div>

          <div className="vitals-grid">
            <Vital label="Role" value={patient.role} />
            <Vital label="Username" value={patient.username || "n/a"} mono className="span-2" />
            <Vital label="Password" value={maskPassword(patient.password)} mono />
            <Vital label="Lease duration" value={patient.leaseDuration ? `${patient.leaseDuration}s` : "n/a"} />
            <Vital label="Issued at" value={formatTime(patient.issuedAt)} />
            <Vital label="Expires at" value={formatTime(patient.expiresAt)} />
            <Vital label="Lease ID" value={patient.leaseId || "n/a"} mono className="span-2" />
            <Vital label="Status" value={patient.status} />
            <Vital
              label="Last pulse"
              value={
                patient.testResult?.ok
                  ? "alive"
                  : patient.testResult?.error
                  ? "failed"
                  : "n/a"
              }
            />
          </div>
        </section>

        <section className="card">
          <div className="panel-header compact">
            <div>
              <p className="panel-label">Events</p>
              <h3>Timeline</h3>
            </div>
          </div>

          <div className="event-list">
            {mergedEvents.length === 0 ? (
              <p className="empty-state">No events yet. Admit a patient.</p>
            ) : (
              mergedEvents.map((event) => (
                <div key={event.id} className={`event-item event-${event.level}`}>
                  <div className="event-time">
                    {formatTime(event.ts)}
                    {event.source && (
                      <span className={`event-source source-${event.source}`}>
                        {event.source}
                      </span>
                    )}
                  </div>
                  <div className="event-message">{event.message}</div>
                </div>
              ))
            )}
          </div>
        </section>
      </aside>
    </div>
  );
}

function Vital({ label, value, mono = false, className = "" }) {
  return (
    <div className={`vital ${className}`}>
      <div className="vital-label">{label}</div>
      <div className={`vital-value ${mono ? "mono" : ""}`}>{value}</div>
    </div>
  );
}