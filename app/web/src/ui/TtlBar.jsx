// Time drawn to scale: the bar's length is the exact fraction of time left.
export default function TtlBar({ label, seconds, total, tone = "idle", empty = "n/a" }) {
  const known = total > 0 && seconds >= 0;
  const pct = known ? Math.max(0, Math.min(100, (seconds / total) * 100)) : 0;
  return (
    <div className={`ttl tone-${tone}`}>
      <div className="ttl-head">
        <span className="label">{label}</span>
        <span className="ttl-value">{known ? `${seconds}s` : empty}</span>
      </div>
      <div
        className="ttl-track"
        role="meter"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={total || 0}
        aria-valuenow={known ? seconds : 0}
      >
        <div className="ttl-fill" style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}
