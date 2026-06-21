# Voicely — Design System ("Frostpane")

> Locked June 21 2026. Register: product. Strategy: Restrained + one cool accent.
> **Supersedes the previous warm-amber identity** (Voicely is now a commercial,
> privacy-led, bilingual product — icy reads as intellectual calm + anti-cloud).
> Source: master strategy §5. North stars: Linear, Raycast/Arc, Things 3.

## Color — icy, light-first

Cool, glacial, intellectual. Light by default with a refined dark variant. The
only loud color is `live`, used **exclusively while capturing audio**.

| Token | Light | OKLCH (approx) | Use |
|---|---|---|---|
| `bg` | `#FBFDFE` | `oklch(0.99 0.004 220)` | window background (faint blue cast) |
| `surface` | `#F3F7FA` | `oklch(0.97 0.006 225)` | cards, panels |
| `surface-2` | `#E8EFF4` | `oklch(0.94 0.008 230)` | sidebars, inset |
| `hairline` | `rgba(14,26,36,0.10)` | — | 0.5px borders (depth = hairline + shadow, not blur) |
| `text` | `#0E1A24` | `oklch(0.23 0.02 235)` | deep slate ink (never `#000`) |
| `text-muted` | `#5A6B78` | `oklch(0.52 0.02 235)` | secondary |
| `accent` | `#3AA8C9` | `oklch(0.69 0.10 222)` | glacier — links, interactive, selection |
| `accent-strong` | `#1B7C9E` | `oklch(0.55 0.10 230)` | pressed/focus, text-on-wash, primary button |
| `accent-wash` | `#E6F4F8` | `oklch(0.96 0.02 220)` | the only tinted fill (hover/selection) |
| **`live`** | `#22D3EE` | `oklch(0.80 0.13 200)` | **electric cyan — ONLY while recording** |
| `success` | `#2BA88C` | teal-green | done/confirmed |
| `warn` | `#B8862B` | brass | caution |
| `danger` | `#C2553C` | terracotta | errors (never fire-engine red) |

**Dark variant:** base `#0A1219` (deep slate, not black); `surface #121C24`;
`text #E6EEF3`; same `accent`/`live`. Every color must read in both modes.

## Type — bilingual by design
- **Latin:** **Geist** (geometric Swiss-rational, free variable) + **Geist Mono**
  (timers, model names, hotkeys, the dev/"vibe-coding" signal).
- **Hebrew:** **Heebo** (Geist has no Hebrew coverage — never fall back to system).
  Stack `"Geist", "Heebo", system-ui`; per-script detection in SwiftUI sets font +
  `.environment(\.layoutDirection, .rightToLeft)` for Hebrew. (Alts: Assistant, Rubik.)
- **Weights 400 / 500 / 600 only** (never 700). Scale 8 steps, 1.2 ratio:
  `11 mono-caption · 12 caption · 13 label · 15 body · 17 body-lg · 20 title · 26 display · 34 hero`.
  Display/hero tracking −0.01em; line-height 1.5 body / 1.15 display. Sentence case.

## Material — "icy without cheesy glass"
- **Glass is a HUD-only material, used once.** The floating recording HUD is the
  single frosted surface (`.ultraThinMaterial` / macOS 26 `.glassEffect`). Never
  stack glass on glass; tint only for meaning. **Everything else is opaque** —
  solid `surface` fills, 0.5px hairlines, depth from shadow not blur
  (`0 1px 2px rgba(14,26,36,.06)` resting; `0 8px 30px rgba(0,0,0,.12)` HUD only).
  Icy comes from the cool palette + hairlines, not from blurring everything.

## Motion
- 120ms micro · 200ms standard · 320ms entrance · `cubic-bezier(0.22,1,0.36,1)` (ease-out-quart).
- The **live orb "breathes"** (1.6s, scale 1.0→1.06, glow on `live`) — the *only*
  ambient animation. Waveform reacts to real RMS. Cleanup cross-fades cyan→success.
  No springs, no parallax, no confetti.

## Per-surface direction
- **Floating HUD (the hero):** frosted capsule, centered-bottom on hotkey-down.
  Left: state orb (idle → breathing live-cyan → success sparkles). Center: live
  waveform (cyan) → streaming transcript during cleanup. Right: mono pill
  (timer / `EN`·`עב`·auto / `AI`). Hebrew renders RTL in-place.
- **Menu-bar:** monochrome template soundwave glyph; **solid live-cyan while capturing**
  (the menu bar itself confirms recording). Click → small frosted popover: mode
  segment, language indicator, last transcript, gear → Settings.
- **Settings:** opaque, native-Mac, NOT glass. `surface` cards, 0.5px hairline,
  radius 12. Accent only on active row + primary buttons.
- **Onboarding:** 4 calm steps on cool `bg`; step 2 = grant Mic + Accessibility with
  a live "test your hotkey" showing the real HUD (the conversion moment).
- **Marketing hero:** deep-slate `#0A1219`→`#1B3540`; oversized frosted HUD mid-capture
  with glowing live orb; Geist 34px headline; mono kicker `on-device · english ⇄ עברית`.

## Bans
Glassmorphism everywhere · neon glow on static elements (cyan is for live state only) ·
`#000`/`#fff` · rainbow/mesh/aurora backgrounds · generic Inter + default Hebrew fallback ·
over-animation · centered-three-identical-feature-cards + gradient CTA · em dashes in copy ·
weight 700. No dock icon.
