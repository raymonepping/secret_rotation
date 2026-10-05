# Prompt podman/05.01 — Design system: extract, write down, apply

Read `prompts/podman/00_01_brief.md` first. Requires 04.01.

## Why this prompt exists

The vault_reference portal has a calm, readable design: daylight ground,
frosted panes, graphite ink, and colour used only for state. It is written
down in `home/DESIGN.md` but tied to that portal (static pages, a 15-page
rail, legacy variable mappings). This repo's UI is a dark "ICU monitor"
with one-off colours per element and gradients on every button. The goal is
one design language across the two projects, with this repo's own
`DESIGN.md` as the portable source of truth.

## Goal

`DESIGN.md` at the repo root describes a design system that does not depend
on vault_reference to be understood, and `app/web` follows it without any
change to what the lanes do.

## Reference

- `vault_reference/home/DESIGN.md`, `home/assets/portal.css`,
  `home/assets/shell.js`, `home/assets/fonts/`
- This repo: `app/web/src/**`

## What to take, and what to adapt

Take as is:

- Ground and ink: pale mineral ground with the 180px mullion, graphite ink,
  frosted white panes with a hairline edge and soft shadow.
- Colour means state, with the same five tokens and values: teal ok, red
  denied, amber warn, azure authority, violet cipher. Nothing is coloured
  for decoration.
- Type: Hanken Grotesk and JetBrains Mono, self-hosted (copy the woff2 and
  licence files), no font CDN.
- Shell: left rail with brand, named groups, colour legend in the rail foot;
  slim sticky top bar with title, subtitle and live context; rail becomes a
  sheet below 1024px.
- Components: pane, page head, button (primary ink, quiet, amber, danger),
  status pill, key/value row, code well, verdict block, the footer
  signature.

Adapt for this app:

- Lane state map: `idle` → ink-3, `stable` → ok, `warning` → warn,
  `critical`/`flatline`/`failed` → denied, `rotating` → warn, `success` → ok.
- Identity values (role, username, connection) in azure; credential
  material (password, lease id) in violet mono.
- The ECG monitor stays, as a light "well" with a fine grid; the trace takes
  the state colour. The sweep and pulse animations stay, but honour
  `prefers-reduced-motion`. Critical pulsing becomes a red edge, not a glow.
- Rail groups: "Lanes" (Patient, Doctor, Surgeon as in-page anchors with
  scroll-spy), "Platform" (seal, vault, database, agent status from
  `/api/platform`), "Tools" (Vault UI on the vault-1 port). Top bar context:
  vault-s seal state, vault-1 state, Auto Mode toggle.
- Destructive actions (Revoke, Rotate DB Root) are visibly different
  (danger); rotations are amber, issues are primary.

Leave:

- The legacy variable mapping (`--bg`, `--green`, …). This app has no old
  pages to carry; use `--vr-*` names only.
- Frost as encryption state (Durin), emoji, gradients on buttons, dark mode.

## Deliverables

1. `DESIGN.md` at the repo root: direction, tokens table (name, value,
   meaning), type, spacing and radius, shell, every component with its
   class names and when to use it, state colour rules, motion and
   accessibility rules, "how to add a lane", and a short "lineage" section
   naming vault_reference and what differs from it.
2. `app/web/src/styles/tokens.css`, `base.css`, `components.css`,
   `shell.css`; `app/web/src/assets/fonts/` with licences. Remove
   `App.css`, `index.css`, old `styles.css`, unused Vite assets.
3. React: `components/Shell.jsx` (rail, top bar, legend, sheet toggle),
   `components/Pane.jsx`, `StatusPill.jsx`, `KeyValue.jsx`, `Verdict.jsx`;
   lane components restyled to use them. `PlatformPanel.jsx` reads
   `/api/platform` every 5s.
4. The event timeline shows each event's source as a small label and its
   level as state colour; Vault's verbatim error appears in a verdict block
   when a call fails.
5. `index.html`: title "Vault Secret Theatre", favicon matching the brand
   mark, `theme-color` the ground colour.
6. Screenshots at 1440×900 and 390×844 into `docs/screenshots/`, taken
   with the stack running and a patient admitted.

## Design rules

- Behaviour is frozen: same buttons, same timers, same API calls.
- Contrast: text and controls meet WCAG AA on the ground and on panes.
- No request to another origin from the page.
- Lint passes (`npm run lint`), build passes.

## Validation

```bash
make app-rebuild && make verify
cd app/web && npm run lint && npm run build
grep -rn 'fonts.googleapis\|cdn\.' app/web/src app/web/index.html   # no output
grep -rn '#07111f\|#3d78ff\|#2b5dd2\|#6ef0ab' app/web/src         # no output (old dark theme)
```

Open `http://127.0.0.1:13001` at 1440 and 390 wide; switch Auto Mode on and
watch one full patient lease expire and re-issue.
