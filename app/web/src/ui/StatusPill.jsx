import { statusTone } from "../lib/format";

// A state, in words, with a dot. `tone` overrides the lane status map.
export default function StatusPill({ status, tone, label, live = false }) {
  const t = tone || statusTone(status);
  return (
    <span className={`pill tone-${t} ${live ? "live" : ""}`} aria-live="polite">
      {label || status}
    </span>
  );
}
