import { useEffect, useMemo, useRef, useState } from "react";
import { API_BASE } from "../api";
import { apiError, formatTime, maskPassword, shortenLeaseId, statusTone } from "../lib/format";
import KeyValue from "../ui/KeyValue";
import Pane from "../ui/Pane";
import StatusPill from "../ui/StatusPill";
import TtlBar from "../ui/TtlBar";
import Verdict from "../ui/Verdict";

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

// One heartbeat period of the trace, drawn twice so the drift loops seamlessly.
const BEAT =
  "110,110 160,108 190,111 220,110 260,112 320,110 360,110 400,110 430,60 455,140 485,85 515,110 620,110 700,110 760,108 810,111 860,110 900,112 950,110 980,110 1010,70 1035,145 1065,88 1095,110 1200,110";
const TRACE = `0,110 ${BEAT} ${BEAT.split(" ")
  .map((p) => {
    const [x, y] = p.split(",");
    return `${Number(x) + 1200},${y}`;
  })
  .join(" ")}`;
const FLAT = "0,110 2400,110";

const LEVEL_TONE = { success: "ok", warning: "warn", critical: "denied", info: "idle" };

function nowTs() {
  return new Date().toISOString();
}

function computeStatus(secondsRemaining, currentStatus) {
  if (currentStatus === "flatline") return "flatline";
  if (secondsRemaining <= 0) return "flatline";
  if (secondsRemaining <= 10) return "critical";
  if (secondsRemaining <= 30) return "warning";
  return "stable";
}

export default function PatientMonitor({ autoMode, sharedEvents }) {
  const [patient, setPatient] = useState(initialState);
  const [localEvents, setLocalEvents] = useState([]);
  const [failure, setFailure] = useState(null);
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
        throw apiError(response, data, "Failed to issue secret");
      }

      // Count down from the lease duration on this browser's clock. Vault
      // enforces the duration on its own clock; the absolute expires_at from
      // the server is off by however far the Podman VM clock drifted.
      const issuedAt = new Date().toISOString();
      const expiresAt = new Date(Date.now() + data.lease_duration * 1000).toISOString();
      const secondsRemaining = data.lease_duration;

      resetThresholdRefs();
      setFailure(null);

      setPatient({
        role: data.role,
        leaseId: data.lease_id,
        username: data.username,
        password: data.password,
        leaseDuration: data.lease_duration,
        issuedAt,
        expiresAt,
        secondsRemaining,
        status: "stable",
        testResult: null,
      });

      addLocalEvent(`Patient admitted. Lease issued for ${data.username}`, "success");

      setTimeout(() => {
        performPulseCheck({ silent: false });
      }, 250);
    } catch (error) {
      setFailure({ title: "Issue a dynamic credential", path: `database/creds/${patient.role}`, error: error.message, vaultStatus: error.vaultStatus });
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
        throw apiError(response, data, "Revoke failed");
      }

      setPatient((prev) => ({
        ...prev,
        status: "flatline",
        secondsRemaining: 0,
      }));

      addLocalEvent("Lease revoked. Flatline detected", "critical");
    } catch (error) {
      setFailure({ title: "Revoke the lease", path: "sys/leases/revoke", error: error.message, vaultStatus: error.vaultStatus });
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

  const tone = statusTone(patient.status);
  const lastPulse = patient.testResult?.ok ? "alive" : patient.testResult?.error ? "failed" : "n/a";

  return (
    <div className="lane-grid">
      <Pane
        id="patient"
        eyebrow="Dynamic secret · lease"
        title="Patient"
        tone={tone === "warn" || tone === "denied" ? tone : undefined}
        aside={<StatusPill status={patient.status} live={patient.status === "critical"} />}
      >
        <div className="lane-body">
          <p className="lede">
            Vault creates a PostgreSQL role on request and drops it when the lease ends. Revoke ends it now.
          </p>

          <div className={`monitor tone-${tone}`} data-status={patient.status}>
            <div className={`monitor-trace ${patient.status !== "flatline" && patient.status !== "idle" ? "pulse" : ""}`}>
              <svg viewBox="0 0 2400 220" preserveAspectRatio="none" aria-hidden="true">
                <polyline points={patient.status === "flatline" || patient.status === "idle" ? FLAT : TRACE} />
              </svg>
            </div>
            <div className="monitor-sweep" aria-hidden="true" />
            <div className="monitor-word" aria-hidden="true">{patient.status.toUpperCase()}</div>

            <div className="monitor-readout">
              <div className="readout">
                <span className="label">Seconds left</span>
                <span className="readout-value tabular">{patient.secondsRemaining}</span>
              </div>
              <div className="readout grow">
                <span className="label">Lease</span>
                <span className="readout-value mono" title={patient.leaseId || "n/a"}>
                  {shortenLeaseId(patient.leaseId)}
                </span>
              </div>
            </div>
          </div>

          <TtlBar label="Lease remaining" seconds={patient.secondsRemaining} total={patient.leaseDuration} tone={tone} />

          {failure && <Verdict {...failure} sentence="Vault did not complete this request." />}

          <div className="btn-row">
            <button type="button" className="btn btn-primary" onClick={handleIssue} disabled={busy.issue}>
              {busy.issue ? "Issuing…" : "Issue secret"}
            </button>
            <button
              type="button"
              className="btn btn-quiet"
              onClick={handleTest}
              disabled={busy.test || !patient.username || patient.status === "idle"}
            >
              {busy.test ? "Testing…" : "Test pulse"}
            </button>
            <button
              type="button"
              className="btn btn-danger"
              onClick={handleRevoke}
              disabled={busy.revoke || !patient.leaseId || patient.status === "flatline"}
            >
              {busy.revoke ? "Revoking…" : "Revoke"}
            </button>
          </div>
        </div>
      </Pane>

      <div className="lane-side">
        <Pane eyebrow="Vitals" title="Current secret" as="aside">
          <div className="kv-grid">
            <KeyValue label="Role" value={patient.role} tone="authority" />
            <KeyValue label="Status" value={patient.status} tone={tone} />
            <KeyValue label="Username" value={patient.username || "n/a"} tone="authority" mono wide />
            <KeyValue label="Password" value={maskPassword(patient.password)} tone="cipher" />
            <KeyValue label="Lease duration" value={patient.leaseDuration ? `${patient.leaseDuration}s` : "n/a"} />
            <KeyValue label="Issued at" value={formatTime(patient.issuedAt)} />
            <KeyValue label="Expires at" value={formatTime(patient.expiresAt)} />
            <KeyValue label="Lease ID" value={patient.leaseId || "n/a"} tone="cipher" wide />
            <KeyValue
              label="Last pulse"
              value={lastPulse}
              tone={lastPulse === "alive" ? "ok" : lastPulse === "failed" ? "denied" : undefined}
            />
          </div>
        </Pane>

        <Pane eyebrow="Events" title="Timeline" as="aside">
          {mergedEvents.length === 0 ? (
            <p className="empty">No events yet. Admit a patient.</p>
          ) : (
            <ol className="timeline" aria-live="polite">
              {mergedEvents.map((event) => (
                <li key={event.id} className={`tone-${LEVEL_TONE[event.level] || "idle"}`}>
                  <span className="timeline-dot" aria-hidden="true" />
                  <span className="timeline-meta">
                    <span className="tabular">{formatTime(event.ts)}</span>
                    {event.source && <span className="timeline-source">{event.source}</span>}
                    <span className="visually-hidden">{event.level}</span>
                  </span>
                  <span className="timeline-msg">{event.message}</span>
                </li>
              ))}
            </ol>
          )}
        </Pane>
      </div>
    </div>
  );
}
