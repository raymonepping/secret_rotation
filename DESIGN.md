# Design system — Daylight Glass

The visual language of the Vault Secret Theatre. It is extracted from the
`vault_reference` portal (which took it from the Durin console) and written
down here so that it stands on its own: everything you need to build a
screen in this style is in this file and in `app/web/src/styles/`.

Source of truth for values: `app/web/src/styles/tokens.css`. Components:
`components.css` and `shell.css`. Where this file and the CSS disagree, the
CSS shipped; fix this file.

## Direction

**Daylight office glazing.** A pale mineral ground with a thin aluminium
mullion every 180px, frosted white panes with a hairline edge and a soft
shadow, graphite ink. A presenter drives the screen on a laptop while others
read along, so state must be readable at a glance from two metres away.

Three rules carry the whole system:

1. **Colour means state.** A coloured thing on screen is a claim about Vault
   or the database. Nothing is coloured for decoration, nothing is coloured
   "for brand".
2. **Machines speak mono.** Anything Vault or PostgreSQL produced (paths,
   lease ids, usernames, passwords, errors) is set in JetBrains Mono. People
   speak Hanken Grotesk.
3. **Vault's answer, verbatim.** Next to every human sentence about a result
   sits what Vault actually said: status code, path, error text.

## Colour

### Ground, structure, ink

| Token | Value | Use |
| --- | --- | --- |
| `--vr-ground` | `#e9eef3` | The building behind the glass. Page background base. |
| `--vr-mullion` | `#aeb9c6` | Frame lines, idle trace, scrollbars. Decorative, never text. |
| `--vr-ink` | `#0f1a2a` | Text, primary button, current rail item. |
| `--vr-ink-2` | `#3e4c5f` | Secondary text, ledes. |
| `--vr-ink-3` | `#526073` | Labels, meta, timestamps, idle state. AA on every ground used here. |
| `--vr-line` | `rgb(15 26 42 / .11)` | Hairlines between and around panes. |
| `--vr-pane` | `rgb(255 255 255 / .62)` | Frosted pane. |
| `--vr-pane-strong` | `rgb(255 255 255 / .82)` | Rail, top bar, footer: the frame, not objects in it. |
| `--vr-well` | `rgb(15 26 42 / .045)` | Inset areas: code, key/value rows, the monitor screen. |

### State

| Token | Value | Soft fill | Means |
| --- | --- | --- | --- |
| `--vr-ok` | `#0f766e` teal | `--vr-ok-soft` `#ccfbf1` | Allowed, healthy, alive, unsealed, rotated successfully. |
| `--vr-denied` | `#c81e1e` red | `--vr-denied-soft` `#fee2e2` | Refused, down, sealed, flatline, destructive action. |
| `--vr-warn` | `#b45309` amber | `--vr-warn-soft` `#fef3c7` | Attention: lease running out, rotation in progress, rotate actions. |
| `--vr-authority` | `#0369a1` azure | `--vr-authority-soft` `#e0f2fe` | Identity: which role, which user, which connection, which token. Also the focus ring. |
| `--vr-cipher` | `#6d28d9` violet | `--vr-cipher-soft` `#ede9fe` | Credential material: passwords, lease ids, key names. |

**One meaning per hue.** Never reuse a state colour for chrome. An accent is
not a state: the "current" rail item is ink, not a colour. Every state colour
is also named in text (a pill label, a legend entry), so no state depends on
colour alone.

### Lane state map (this app)

| Lane status | Tone | Why |
| --- | --- | --- |
| `idle` | ink-3 | Nothing issued yet. Not a problem, not a success. |
| `stable`, `success` | ok | The credential works / the action succeeded. |
| `warning`, `rotating` | warn | Needs attention, or Vault is changing something right now. |
| `critical`, `flatline`, `failed` | denied | About to die, dead, or Vault refused. |

## Type

| Role | Class | Size / weight | Use |
| --- | --- | --- | --- |
| page | `.h-page` | 1.75rem / 700, -0.022em | One per screen. |
| section | `.h-section` | 1.08rem / 700 | Pane titles. |
| eyebrow | `.eyebrow` | 0.8rem / 700, uppercase, 0.07em | Above a title: what kind of thing this is ("Dynamic secret"). |
| body / lede | `.lede` | 1rem / 400, lh 1.55, max 68ch | Explanations. |
| label | `.label` | 0.8rem / 600, ink-3 | Key/value keys, field labels. |
| meta | `.meta` | 0.82rem / 400, ink-3 | Timestamps, captions. |
| mono | `.mono` | 0.82rem JetBrains Mono | Machine output. |

Root size is **15px**. The floor for any text is **0.8rem (12px)**. Numbers
that change (TTLs, counters, clocks) use `font-variant-numeric: tabular-nums`
(`.tabular`) so they do not jitter.

Both families are variable fonts, self-hosted from
`app/web/src/assets/fonts/` under the SIL Open Font License (licence files
alongside). The page makes no request to another origin; the
Content-Security-Policy enforces it.

## Space and shape

| Token | Value | Use |
| --- | --- | --- |
| `--vr-radius-pane` | 14px | Panes. |
| `--vr-radius-control` | 9px | Buttons, wells, fields, key/value rows. |
| pill | 999px | Status pills, legend dots, toggles. |
| gutter | 16px phone, 32px desktop | Page padding. |
| stack | 20px | Gap between panes. |
| pane padding | 20px (24px ≥ 1024px) | Inside panes. |

The rail, top bar and footer are square: they are the building, not objects
in it.

## Depth and motion

Depth comes from glass, not stacked shadows: pane = translucent white,
`backdrop-filter: blur(22px) saturate(150%)`, a 1px white inset highlight,
a hairline, and one soft offset shadow (`--vr-shadow`).

Motion is short and means something: a state change (`200ms`, ease
`cubic-bezier(.16,1,.3,1)`), a rotation in progress, the monitor's sweep. No
ambient animation that does not report state. `prefers-reduced-motion`
reduces every transition and animation to an instant.

## Shell

- **Rail** (left, 15.5rem, `pane-strong`): brand mark and name, then named
  groups of links, then the colour legend in the rail foot. The current item
  is an ink pill (`aria-current`). Below 1024px the rail is a sheet opened from
  the top bar's menu button, over a scrim.
- **Top bar** (sticky, `pane`): title and subtitle on the left; live context
  on the right (here: vault-s seal state, vault-1 state, Auto Mode).
- **Footer** (in flow, never fixed): signature, three words, nothing else.

## Components

| Component | Class / file | Use |
| --- | --- | --- |
| Pane | `.pane` / `Pane.jsx` | Every grouped box. Optional head: eyebrow, title, aside (pill or actions). |
| Page head | `.page-head` | Eyebrow, `.h-page`, `.lede`. Once per screen. |
| Button | `.btn` + `.btn-primary` (ink), `.btn-quiet` (glass), `.btn-amber`, `.btn-danger` | Primary = the expected next step. Amber = rotate/change. Danger = revoke/destroy. Quiet = everything else. Destructive actions are always visibly different. |
| Status pill | `.pill` + `.tone-*` / `StatusPill.jsx` | A state, in words, with a dot. Uppercase label. |
| Key/value | `.kv` / `KeyValue.jsx` | Label over value in a well. `tone="authority"` for identities, `tone="cipher"` (mono) for credential material. |
| TTL bar | `.ttl` / `TtlBar.jsx` | Time drawn to scale: the bar's length is the exact fraction left. Tone follows the lane state. |
| Verdict | `.verdict` / `Verdict.jsx` | ALLOWED/DENIED, the human sentence, and Vault's verbatim status and error in mono. Shown when a call fails. |
| Timeline | `.timeline` | Newest first. Level as a coloured dot plus text; source as a small mono tag. |
| Monitor well | `.monitor` | The Patient lane's ECG: a `--vr-well` screen with a fine grid; the trace takes the state colour. |
| Toggle | `.toggle` | Auto Mode. On = ink track, never a state colour. |
| Legend | `.legend` | Every state colour named once. Lives in the rail foot. |
| Signature | `.sig-name` | Author name in the footer; a light sweeps across on hover/focus. |

## Accessibility

- Text and controls meet WCAG AA on the ground and on panes (`ink-3` is the
  lightest text colour; it passes on the darkest ground).
- Focus: 2px azure outline, 2px offset, on every interactive element.
- Status is never colour alone: pills carry a word, timeline items a level.
- Live regions: the lane status pills are `aria-live="polite"`.
- Touch targets ≥ 2.4rem high.

## How to add a lane

1. A section with an `id`, built from `Pane` (eyebrow = the Vault feature,
   title = the lane name, aside = `StatusPill`).
2. Identities in `KeyValue tone="authority"`, credential material in
   `tone="cipher"`, countdowns in `TtlBar`.
3. Map the lane's statuses onto the tone table above; add no new colours.
4. Add it to the rail's "Lanes" group in `Shell.jsx`.
5. Show Vault's refusal with `Verdict`.

## Lineage

`vault_reference/home/DESIGN.md` → this file. Same tokens, values and rules.
Differences:

- No legacy variable names (`--bg`, `--green`, …): this app had no old pages
  to carry. Use `--vr-*` only.
- Buttons, key/value rows, TTL bar and verdict are defined here as shared
  classes; the portal left them to each page.
- The legend sits in the rail foot, as in the portal; the footer is in flow,
  as in Durin.
- Durin's frosted-value component is not used: there, frost *is* the
  encryption state; here it would be decoration.
