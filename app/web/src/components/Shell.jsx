import { useEffect, useState } from "react";

// Rail icons: 24×24 stroke paths.
const I = {
  patient: "M3 12h4l3-8 4 16 3-8h4",
  doctor: "M15 7a4 4 0 11-3.9 5H8v3H5v-3H3v-3h8.1A4 4 0 0115 7z",
  surgeon: "M4 12a8 8 0 0114-5l2-2v6h-6l2-2a5 5 0 00-9 3M20 12a8 8 0 01-14 5l-2 2v-6h6l-2 2a5 5 0 009-3",
  platform: "M4 5h16v6H4zM4 13h16v6H4zM8 8h.01M8 16h.01",
  ext: "M14 4h6v6M20 4l-9 9M19 14v6H4V5h6",
};

const LANES = [
  ["patient", "Patient", "dynamic"],
  ["doctor", "Doctor", "root"],
  ["surgeon", "Surgeon", "static"],
];

const LEGEND = [
  ["ok", "Alive / allowed"],
  ["denied", "Refused / dead"],
  ["warn", "Attention"],
  ["authority", "Identity"],
  ["cipher", "Credential"],
];

const VAULT_UI = `https://${location.hostname}:${import.meta.env.VITE_VAULT_UI_PORT || "18200"}/ui/`;

function Icon({ name }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d={I[name]} />
    </svg>
  );
}

export function BrandMark() {
  return (
    <svg viewBox="0 0 32 32" aria-hidden="true">
      <path d="M16 2l12 7v14l-12 7-12-7V9z" fill="#0f1a2a" />
      <path d="M7 16.5h5l2-4.5 3 9 2-4.5h6" fill="none" stroke="#e9eef3" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

// Which section is on screen: the rail marks it as current.
function useScrollSpy(ids) {
  const [current, setCurrent] = useState(ids[0]);
  useEffect(() => {
    const seen = new Map();
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => seen.set(e.target.id, e.intersectionRatio));
        let best = null;
        let ratio = 0;
        ids.forEach((id) => {
          if ((seen.get(id) || 0) > ratio) {
            ratio = seen.get(id);
            best = id;
          }
        });
        if (best) setCurrent(best);
      },
      { rootMargin: "-64px 0px -35% 0px", threshold: [0, 0.15, 0.4, 0.7, 1] },
    );
    ids.forEach((id) => {
      const el = document.getElementById(id);
      if (el) observer.observe(el);
    });
    return () => observer.disconnect();
  }, [ids]);
  return current;
}

const SPY_IDS = ["patient", "doctor", "surgeon", "platform"];

function nodeState(n, { active } = {}) {
  if (!n) return ["checking", "idle"];
  if (!n.reachable) return ["unreachable", "denied"];
  if (!n.initialized) return ["uninitialized", "warn"];
  if (n.sealed) return ["sealed", "denied"];
  if (active) return [n.standby ? "standby" : "active", n.standby ? "warn" : "ok"];
  return ["unsealed", "ok"];
}

export default function Shell({ platform, autoMode, setAutoMode, children }) {
  const [open, setOpen] = useState(false);
  const current = useScrollSpy(SPY_IDS);
  const [sealLabel, sealTone] = nodeState(platform?.seal);
  const [vaultLabel, vaultTone] = nodeState(platform?.vault, { active: true });

  const link = (id, label, icon, hint) => (
    <a
      key={id}
      className="rail-link"
      href={`#${id}`}
      aria-current={current === id ? "true" : undefined}
      onClick={() => setOpen(false)}
    >
      <Icon name={icon} />
      {label}
      {hint && <span className="rail-hint">{hint}</span>}
    </a>
  );

  return (
    <div className={`shell ${open ? "open" : ""}`}>
      <nav className="rail" aria-label="Secret Theatre">
        <a className="brand" href="#top">
          <BrandMark />
          <span>
            <span className="brand-name">Secret Theatre</span>
            <span className="brand-sub">Vault secret lifecycles</span>
          </span>
        </a>
        <div className="rail-group">
          <div className="rail-group-label">Lanes</div>
          {LANES.map(([id, label, hint]) => link(id, label, id, hint))}
        </div>
        <div className="rail-group">
          <div className="rail-group-label">Platform</div>
          {link("platform", "Status", "platform")}
        </div>
        <div className="rail-group">
          <div className="rail-group-label">Tools</div>
          <a className="rail-link ext" href={VAULT_UI} target="_blank" rel="noopener noreferrer">
            <Icon name="ext" />
            Vault UI
          </a>
        </div>
        <div className="rail-foot">
          <div className="legend">
            {LEGEND.map(([tone, label]) => (
              <span key={tone} className={`tone-${tone}`}>
                <i aria-hidden="true" />
                {label}
              </span>
            ))}
          </div>
        </div>
      </nav>
      <button type="button" className="scrim" aria-label="Close navigation" onClick={() => setOpen(false)} />

      <header className="bar" id="top">
        <button type="button" className="menu-btn" aria-label="Open navigation" onClick={() => setOpen(true)}>
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M4 7h16M4 12h16M4 17h16" />
          </svg>
        </button>
        <div>
          <div className="bar-title">Patient Monitor</div>
          <div className="bar-sub">Dynamic, root and static secrets in one control room</div>
        </div>
        <div className="bar-context">
          <div className={`ctx tone-${sealTone} ctx-hide-narrow`}>
            <span className="ctx-label">vault-s</span>
            <span className="ctx-value">{sealLabel}</span>
          </div>
          <div className={`ctx tone-${vaultTone}`}>
            <span className="ctx-label">vault-1</span>
            <span className="ctx-value">{vaultLabel}</span>
          </div>
          <span className="ctx-sep" aria-hidden="true" />
          <label className={`toggle ${autoMode ? "on" : ""}`}>
            <input type="checkbox" checked={autoMode} onChange={(e) => setAutoMode(e.target.checked)} />
            <span className="toggle-track">
              <span className="toggle-knob" />
            </span>
            Auto mode
          </label>
        </div>
      </header>

      <main className="main">{children}</main>

      <footer className="footer">
        <div className="footer-inner">
          <span>
            © {new Date().getFullYear()}{" "}
            <span className="sig-name" data-name="Raymon Epping" tabIndex={0}>
              Raymon Epping
            </span>
          </span>
          <span className="footer-quote">The database holds the data. Vault holds the keys to it.</span>
          <span className="footer-words">
            <span>Issue</span>
            <span>Rotate</span>
            <span>Revoke</span>
          </span>
        </div>
      </footer>
    </div>
  );
}
