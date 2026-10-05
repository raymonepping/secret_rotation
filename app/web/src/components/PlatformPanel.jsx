import Pane from "../ui/Pane";
import StatusPill from "../ui/StatusPill";

function vaultTile(name, role, n) {
  let label = "checking";
  let tone = "idle";
  if (n) {
    if (!n.reachable) [label, tone] = ["unreachable", "denied"];
    else if (!n.initialized) [label, tone] = ["uninitialized", "warn"];
    else if (n.sealed) [label, tone] = ["sealed", "denied"];
    else [label, tone] = ["unsealed", "ok"];
  }
  return (
    <div className="tile" key={name}>
      <div className="tile-head">
        <span className="tile-name mono">{name}</span>
        <StatusPill tone={tone} label={label} />
      </div>
      <dl>
        <dt>Role</dt>
        <dd>{role}</dd>
        <dt>Version</dt>
        <dd className="mono">{n?.version || "n/a"}</dd>
        {n?.error && (
          <>
            <dt>Error</dt>
            <dd className="mono">{n.error}</dd>
          </>
        )}
      </dl>
    </div>
  );
}

// The platform under the lanes: seal node, Vault, database, the API's identity.
export default function PlatformPanel({ platform, error }) {
  const id = platform?.identity;
  const pg = platform?.postgres;
  return (
    <Pane
      id="platform"
      eyebrow="Platform · refreshed every 5s"
      title="What the lanes stand on"
      aside={error ? <StatusPill tone="denied" label="API unreachable" /> : null}
    >
      <div className="platform-grid">
        {vaultTile("vault-s", "Transit auto-unseal provider (Shamir 1-of-1)", platform?.seal)}
        {vaultTile("vault-1", "Application Vault (auto-unseals via vault-s)", platform?.vault)}
        <div className="tile">
          <div className="tile-head">
            <span className="tile-name mono">postgres</span>
            <StatusPill tone={!pg ? "idle" : pg.reachable ? "ok" : "denied"} label={!pg ? "checking" : pg.reachable ? "reachable" : "down"} />
          </div>
          <dl>
            <dt>Database</dt>
            <dd className="mono">{pg?.database || "n/a"}</dd>
            <dt>Connection</dt>
            <dd className="mono ident">{platform?.names?.connection || "n/a"}</dd>
          </dl>
        </div>
        <div className="tile">
          <div className="tile-head">
            <span className="tile-name">API identity</span>
            <StatusPill tone={!id ? "idle" : id.valid ? "ok" : "denied"} label={!id ? "checking" : id.valid ? "token valid" : "no token"} />
          </div>
          <dl>
            <dt>Via</dt>
            <dd>Vault Agent · AppRole</dd>
            <dt>Name</dt>
            <dd className="mono ident">{id?.display_name || "n/a"}</dd>
            <dt>Policies</dt>
            <dd className="mono">{id?.policies?.join(", ") || "n/a"}</dd>
            <dt>Token TTL</dt>
            <dd className="tabular">{id?.valid ? `${id.ttl}s` : "n/a"}</dd>
          </dl>
        </div>
      </div>
    </Pane>
  );
}
