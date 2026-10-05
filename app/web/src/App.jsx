import { useEffect, useState } from "react";
import { API_BASE } from "./api";
import DoctorCard from "./components/DoctorCard";
import PatientMonitor from "./components/PatientMonitor";
import PlatformPanel from "./components/PlatformPanel";
import Shell from "./components/Shell";
import SurgeonCard from "./components/SurgeonCard";

// /api/platform every 5s: seal and vault state for the top bar and the panel.
function usePlatform() {
  const [platform, setPlatform] = useState(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    let stop = false;
    async function poll() {
      try {
        const res = await fetch(`${API_BASE}/api/platform`);
        const data = await res.json();
        if (!stop) {
          setPlatform(data);
          setError(false);
        }
      } catch {
        if (!stop) setError(true);
      }
    }
    poll();
    const t = setInterval(poll, 5000);
    return () => {
      stop = true;
      clearInterval(t);
    };
  }, []);
  return [platform, error];
}

export default function App() {
  const [sharedEvents, setSharedEvents] = useState([]);
  const [autoMode, setAutoMode] = useState(false);
  const [platform, platformError] = usePlatform();
  const names = platform?.names || {};

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

  return (
    <Shell platform={platform} autoMode={autoMode} setAutoMode={setAutoMode}>
      <div className="page-head">
        <p className="eyebrow">Vault Secret Theatre</p>
        <h1 className="h-page">Three secret lifecycles, live against PostgreSQL</h1>
        <p className="lede">
          A dynamic credential that lives for a minute, a static account whose password Vault rotates, and the
          root credential Vault takes away from everyone else. Auto Mode drives all three.
        </p>
      </div>

      <PatientMonitor autoMode={autoMode} sharedEvents={sharedEvents} />
      <DoctorCard autoMode={autoMode} addSharedEvent={addSharedEvent} connection={names.connection || "hospital-postgres"} />
      <SurgeonCard autoMode={autoMode} addSharedEvent={addSharedEvent} role={names.staticRole || "surgeon"} />
      <PlatformPanel platform={platform} error={platformError} />
    </Shell>
  );
}
