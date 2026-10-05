// A frosted pane. Optional head: eyebrow (what kind of thing), title, aside.
export default function Pane({ id, eyebrow, title, aside, tone, className = "", children, as = "section", ...rest }) {
  const Tag = as;
  return (
    <Tag
      id={id}
      className={`pane ${tone ? `tone-${tone}` : ""} ${id ? "section-anchor" : ""} ${className}`}
      data-tone={tone}
      aria-labelledby={id && title ? `${id}-title` : undefined}
      {...rest}
    >
      {(eyebrow || title || aside) && (
        <div className="pane-head">
          <div>
            {eyebrow && <p className="eyebrow">{eyebrow}</p>}
            {title && (
              <h2 className="h-section" id={id ? `${id}-title` : undefined}>
                {title}
              </h2>
            )}
          </div>
          {aside && <div className="pane-head-aside">{aside}</div>}
        </div>
      )}
      {children}
    </Tag>
  );
}
