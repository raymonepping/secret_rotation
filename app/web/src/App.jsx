import { useMemo, useState } from "react";
import DoctorCard from "./components/DoctorCard";
import PatientMonitor from "./components/PatientMonitor";
import SurgeonCard from "./components/SurgeonCard";

export default function App() {
  const [sharedEvents, setSharedEvents] = useState([]);
  const [autoMode, setAutoMode] = useState(false);

  function addSharedEvent(message, level = "info", source = "system") {
    setSharedEvents((prev) => [
      {
        id: crypto.randomUUID(),
        ts: new Date().toISOString(),
        message,
        level,
        source,
      },
      ...prev,
    ]);
  }

  const appContext = useMemo(
    () => ({
      autoMode,
      setAutoMode,
      addSharedEvent,
      sharedEvents,
    }),
    [autoMode, sharedEvents]
  );

  return (
    <div className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Vault Secret Theatre</p>
          <h1>Patient Monitor</h1>
          <p className="subtitle">
            Dynamic, root, and static secret lifecycle in one live control room
          </p>
        </div>

        <div className="topbar-actions">
          <label className={`auto-mode-toggle ${autoMode ? "enabled" : ""}`}>
            <input
              type="checkbox"
              checked={autoMode}
              onChange={(e) => setAutoMode(e.target.checked)}
            />
            <span className="auto-mode-track">
              <span className="auto-mode-knob" />
            </span>
            <span className="auto-mode-label">Auto Mode</span>
          </label>

          <div className="topbar-badge">Dynamic Secrets</div>
        </div>
      </header>

      <main className="stacked-layout">
        <PatientMonitor
          autoMode={appContext.autoMode}
          sharedEvents={appContext.sharedEvents}
          addSharedEvent={appContext.addSharedEvent}
        />

        <DoctorCard
          autoMode={appContext.autoMode}
          addSharedEvent={appContext.addSharedEvent}
        />

        <SurgeonCard
          autoMode={appContext.autoMode}
          addSharedEvent={appContext.addSharedEvent}
        />
      </main>
    </div>
  );
}