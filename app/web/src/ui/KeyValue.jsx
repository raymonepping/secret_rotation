// Label over value in a well. tone="authority" for identities (role, user,
// connection); tone="cipher" for credential material, set in mono.
export default function KeyValue({ label, value, tone, mono = tone === "cipher", wide = false, title }) {
  return (
    <div className={`kv ${wide ? "wide" : ""} ${tone ? `tone-${tone}` : ""}`}>
      <span className="label">{label}</span>
      <div className={`kv-value ${mono ? "mono" : ""}`} title={title}>
        {value}
      </div>
    </div>
  );
}
