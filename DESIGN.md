# Voicely — Design System

> Locked June 21 2026. Register: product. Strategy: Restrained, one accent.

## Color

Accent is **warm amber** — a VU-meter glow / the warmth of voice. One accent carries the whole state arc (idle → listening → done). Deliberately not the Siri-blue/purple voice-app reflex.

| Token | Value (hex) | OKLCH (approx) | Use |
|---|---|---|---|
| `accent` | `#EF9F27` | `oklch(0.76 0.15 70)` | listening state, waveform, primary action, selection |
| `accent-strong` | `#BA7517` | `oklch(0.62 0.13 66)` | text on amber, pressed/active |
| `accent-tint` | `#FAC775` | `oklch(0.85 0.11 78)` | "on" pill fills |

**Neutrals** are tinted warm (toward the amber hue, chroma ~0.006) — never `#000`/`#fff`.
- `text` `oklch(0.22 0.006 70)` · `text-muted` `oklch(0.52 0.006 70)` · `text-hint` `oklch(0.65 0.005 70)`
- `surface` (settings, follows system light/dark) · `surface-2` (grouped rows / panels)

**HUD capsule** is a self-contained dark surface so it reads over *any* app (light or dark):
- `hud-bg` `oklch(0.24 0.004 70)` (≈`#2C2C2A`, warm near-black) · hairline border `rgba(255,255,255,0.16)`
- `hud-text` `#F1EFE8` · `hud-text-muted` `#B4B2A9` · waveform `accent`

## Theme
- **HUD:** always its own dark capsule (does not follow system appearance — it floats over arbitrary apps).
- **Settings + menu:** native, follows system light/dark via the asset catalog / system materials.

## Typography
- System font: SF Pro / `system-ui`. One family, no display/body pairing.
- Fixed rem-equivalent scale, ratio ~1.2. Two weights: regular (400) + medium (500/semibold for emphasis). Sentence case everywhere.
- Sizes: HUD label 14, hints 12; settings labels 13, section headers 12 muted, sublabels 11.

## Layout
- HUD: a pill, ~26 px tall content, centered near screen-bottom (or near cursor — user-set later). Generous internal gaps (14 px); content order: state dot · waveform · label · timer.
- Settings: one scrolling pane, four grouped sections (General · Transcription · AI cleanup · Vocabulary). Grouped rows share a rounded container; no tab-maze.
- Menu dropdown: ≤6 rows, 7 px row padding, ⌘-shortcuts right-aligned and muted.

## Motion
- 150–250 ms, ease-out (quart/quint). State changes only, never decoration.
- HUD waveform: live amplitude via `transform: scaleY` (GPU), never animating layout.
- HUD appear/dismiss: quick fade + slight rise; dismiss after "Copied/Inserted" within ~700 ms.

## State vocabulary (HUD + menu icon)
| State | Menu icon | HUD |
|---|---|---|
| Idle | muted monochrome waveform glyph | hidden |
| Listening (hold) | amber glyph | dark capsule · amber waveform · "Listening" · timer · hint "release to insert" |
| Listening (locked/toggle) | amber glyph | same · hint "tap ⌥ to stop" |
| Cleaning | amber glyph (subtle motion) | "Cleaning up…" + `ti-sparkles` |
| Inserted | amber → idle | brief "Inserted" check, fades |
| Copied-only (fallback) | amber → idle | "Copied · ⌘V to paste" |
| Paused (secure field) | dimmed | "Paused — secure field" |

## Bans (inherited + project)
No gradient text, no glassmorphism-by-default (the HUD is a flat dark surface, not a glass card), no side-stripe borders, no hero-metric template, no em dashes in copy. No Siri-gradient. No dock icon.
