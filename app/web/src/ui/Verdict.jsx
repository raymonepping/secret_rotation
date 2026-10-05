// Vault's answer, verbatim, next to the human sentence.
export default function Verdict({ allowed = false, title, sentence, vaultStatus, path, error }) {
  const tone = allowed ? "ok" : "denied";
  return (
    <div className={`verdict tone-${tone}`} role={allowed ? "status" : "alert"}>
      <div className="verdict-head">
        <span className="verdict-result">{allowed ? "ALLOWED" : "DENIED"}</span>
        {title && <span className="verdict-title">{title}</span>}
      </div>
      {sentence && <p className="verdict-sentence">{sentence}</p>}
      {(vaultStatus || path || error) && (
        <div className="verdict-vault mono">
          {vaultStatus && <span>vault {vaultStatus}</span>}
          {path && <span>{path}</span>}
          {error && <span className="err">{error}</span>}
        </div>
      )}
    </div>
  );
}
