# Research: icy-design-system

Now the rest of the system spec in writing — the parts that don't need a picture but do need to be exact.

---

## 1. Color — "Frostpane" (tokens above, in OKLCH + hex)

The palette is built around a single decision: **the background is barely-blue, the ink is slate not black, and the only saturated thing on screen is the accent.** That restraint is what makes it read "icy intellectual" instead of "tech-bro cyan."

- **Backgrounds are cool whites, not pure white.** `#FBFDFE` bg has a faint blue cast (hue 230) so the screen feels like frosted glass, not paper. Surfaces step down in lightness only (`F3F7FA → E8EFF4`), never in saturation.
- **Ink is deep slate** `#0E1A24`, never `#000`. Pure black against cool whites looks cheap and harsh; slate reads considered.
- **One accent, two strengths.** `accent #3AA8C9` (glacier) for interactive/links, `accent-strong #1B7C9E` for pressed/focus and text-on-wash. `accent-wash #E6F4F8` is the only tinted fill you use for selection and hover.
- **The live/recording accent is deliberately the loudest color in the whole system** — `#22D3EE` electric cyan. It appears *only* while capturing audio. Because nothing else is that saturated, the eye locks onto it instantly. This is the system's one permitted moment of intensity.
- **Semantics stay desaturated** to match the icy register — a muted teal-green success, a brass warn, a terracotta-leaning danger (never fire-engine red).

**Token contract** (ship these as CSS vars + a Swift `Color` extension, identical names):
`bg, surface, surface-2, hairline, text, text-muted, accent, accent-strong, accent-wash, live, success, warn, danger`. Light and dark are the same 13 names with swapped values (dark set above). Dark is a deep slate `#0A1219`, *not* black — keeps the "icy" temperature in the dark.

---

## 2. Typography — crisp grotesque + refined mono, Hebrew-first

**UI / display: Geist (Sans).** It's the right face for this brief — geometric, Swiss-rational, slightly technical, free, ships as a variable font, and pairs with a matching mono. It carries the "intellectual" tone without feeling corporate ([Geist, Google Fonts](https://fonts.google.com/specimen/Geist) / [vercel/geist-font](https://github.com/vercel/geist-font)).

**The Hebrew catch — and the fix.** Geist has **no Hebrew coverage** (confirmed: Latin/Cyrillic only). For a real EN↔HE product you must not let Geist fall back to a system Hebrew font — the registers clash. Use a **per-script font stack**:

- Latin UI → **Geist**
- Hebrew UI → **Heebo** (Oded Ezer's Roboto-matched Hebrew; geometric, modern, variable, near-identical x-height and weight feel to Geist) ([Heebo, Google Fonts](https://fonts.google.com/specimen/Heebo) / [OdedEzer/heebo](https://github.com/OdedEzer/heebo)). Alternate if you want warmer terminals: **Assistant** ([Google Fonts](https://fonts.google.com/specimen/Assistant)) or **Rubik** ([googlefonts/rubik](https://github.com/googlefonts/rubik)) — all three are variable and Hebrew-native.

CSS: `font-family: "Geist", "Heebo", system-ui, sans-serif;` (browser picks Heebo for Hebrew codepoints automatically). SwiftUI: detect script per transcript and set the font; set `.environment(\.layoutDirection, .rightToLeft)` for Hebrew blocks so the HUD text and any review UI mirror correctly.

**Mono: Geist Mono** for the dev/"vibe-coding" angle, timers, model names, hotkey glyphs, and the transcript-in-progress readout ([Geist Mono via vercel/geist-font](https://github.com/vercel/geist-font)). It's the designer-grade sibling of JetBrains Mono and unifies sans+mono into one type system. If you want a paid, more editorial flex for the marketing site only, **Berkeley Mono** is the 2026 connoisseur pick ([overview, madegooddesigns](https://madegooddesigns.com/best-monospace-fonts-2026/)) — but Geist Mono is the shipping default.

**Type scale** (8-step, 1.2 ratio, Geist variable weights — use only 400 / 500 / 600, never 700):
`11 mono-caption · 12 caption · 13 label · 15 body · 17 body-lg · 20 title · 26 display · 34 hero`. Tracking: tighten display/hero to `-0.01em`; mono and 11–12px set at `+0.02em`. Line-height 1.5 body, 1.15 display.

---

## 3. Material & motion — "icy without cheesy glass"

The trap with "icy" is glassmorphism slop: everything blurred, neon glows, frosted cards stacked on frosted cards. The discipline:

**Glass is a HUD-only material, used once.** Per Apple's own macOS 26 guidance, **never stack glass on glass** and group floating glass in a `GlassEffectContainer`; **tint only to convey meaning, never for decoration** ([Liquid Glass, Apple Developer](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass) / [WWDC25 #323](https://developer.apple.com/videos/play/wwdc2025/323/)). So:

- **The floating recording HUD** is the *one* glass surface — frosted, blurring the desktop behind it. On macOS 26 use `.glassEffect(.regular, in: .capsule)`; below 26, bridge `NSVisualEffectView` (`.hudWindow` material, `.behindWindow` blending) via `NSViewRepresentable` ([Ohanaware: SwiftUI macOS Vibrancy](https://ohanaware.com/swift/macOSVibrancy.html)). Never `ultraThinMaterial` for in-app cards — it blurs the desktop, not in-app content, which looks wrong on a panel ([createwithswift: Using materials with SwiftUI](https://www.createwithswift.com/using-materials-with-swiftui/)).
- **Settings, onboarding, every other surface = opaque.** Solid `surface` fills, **hairline borders** (`0.5px`, the `hairline` token), and *soft depth from shadow, not blur*: `0 1px 2px rgba(14,26,36,.06)` resting, `0 8px 30px rgba(0,0,0,.12)` for the floating HUD only. "Icy" comes from the cool palette and hairlines, **not** from blurring everything.
- **Frost accents, sparingly:** a 1px top inner-highlight (`inset 0 0.5px 0 rgba(255,255,255,.5)`) on raised cards reads like light catching an ice edge. Use on the HUD and primary buttons only.

**Motion principles — calm, precise, ease-out:**
- Durations: 120ms micro (hover/press), 200ms standard (panel/sheet), 320ms entrance. Nothing slower; this is a productivity tool.
- Curve: `cubic-bezier(0.22, 1, 0.36, 1)` (ease-out-quart) for entrances; symmetric ease-in-out for the recording pulse.
- **The live orb "breathes"** — a 1.6s scale `1.0 → 1.06` + glow-opacity loop on `#22D3EE`, the only ambient animation in the app. The waveform bars react to real input RMS (not random). When cleanup runs, the orb cross-fades cyan → success-green with the `ti-sparkles` glyph.
- No bounce, no spring overshoot, no parallax. Precision over playfulness.

---

## 4. Surface-by-surface application

**Floating recording HUD (the hero) — rendered above.** A 340px frosted capsule that appears centered-bottom on hotkey-down. Left: the state orb (idle mic → live cyan orb → green sparkles). Center: live waveform during capture, the streaming transcript during cleanup. Right: a mono pill (timer / language / `AI`). It auto-positions above the caret when possible. Hebrew transcripts render RTL inside the same pill. This is the moment that has to feel expensive — it's 90% of the perceived product.

**Menu-bar presence.** A custom monochrome template icon (a stylized soundwave-in-a-pane mark) that tints to the system menu-bar color when idle and goes **solid live-cyan when capturing** — so the menu bar itself confirms recording. Click → a small frosted popover (same glass language as the HUD) with: current mode toggle (Clean/Polish/Prompt as a 3-segment control), language indicator (EN/עב/auto), last-transcript snippet, and a quiet gear → Settings. Keep it under ~280px wide.

**Settings.** Opaque, two-pane (sidebar nav + content), classic macOS, *not* glass. Sidebar uses the system sidebar vibrancy (free, correct). Content cards: `surface` fill, `0.5px hairline` border, `radius 12`. Group into: Dictation (model, hotkey, push-to-talk vs toggle), Languages (EN/HE, translation direction toggle), AI Cleanup (mode + model + custom prompt), Vocabulary, Snippets, Account/License. Accent only on the active sidebar row (`accent-wash` fill + `accent` left bar) and primary buttons. This is where the `settings-hub` restraint matters — flat list, predictable rows, no nested drawers.

**Onboarding.** 4 calm full-window steps on the cool `bg`, generous whitespace, one large hero illustration per step (frost/ice-pane motif), a single primary `accent-strong` CTA: (1) Welcome + the value line, (2) grant Mic + Accessibility permissions with a live "test your hotkey" that shows the real HUD, (3) pick languages + translation, (4) choose cleanup mode. Progress as four hairline dots, active dot = `accent`. The "test your hotkey" step doubling as the permission grant is the conversion moment — the user sees the hero HUD before they've committed.

**Marketing landing hero.** Deep-slate `#0A1219` background washing to `#1B3540`, a single oversized frosted HUD floating center as the product shot with a real waveform mid-capture, the live-cyan orb glowing. Headline in Geist display 34px, one line, slate-on-near-white card or white-on-slate. Subhead in `text-muted`. A mono kicker above it (`ti`-style label like `on-device · english ⇄ עברית`) signals the translation differentiator and the dev credibility. One `accent-strong` "Download for Mac" button + a quiet "also iOS · Windows · Android." Keep the page mostly empty — whitespace *is* the premium signal. Below the fold: three icy feature cards (on-device privacy, translation, AI cleanup) on `surface`, hairline borders, no glass.

---

## 5. Three anchor references + the slop traps

**Anchor aesthetics (real products to study):**
- **Linear** — for the cool near-monochrome palette discipline, hairline borders, restrained single-accent, and the "fast, intellectual, calm" register. This is the closest north star.
- **Arc Browser (and Raycast)** — for the floating-command-surface language: a single beautiful frosted panel that appears over your work, precise motion, mono accents. Raycast specifically for menu-bar-app craft and keyboard-first feel.
- **Things 3 (Cultured Code)** — for *opaque* native-macOS restraint: how to do depth with light and hairlines instead of blur, and how Settings/onboarding feel unmistakably Mac-native and quiet. The antidote to over-glassing.

**AI-slop traps to avoid:**
- **Glassmorphism everywhere** — frosted cards on frosted backgrounds, the whole UI blurred. Glass is *one* surface (the HUD). Everything else opaque.
- **Neon cyan glow on static elements** — the saturated `#22D3EE` is reserved for the *live* state only. Static glowing buttons/borders are the #1 tell.
- **Pure black `#000` + pure white `#FFF`** — kills the icy temperature. Always slate ink + cool whites.
- **Rainbow gradients / mesh / aurora backgrounds** — the lazy "AI app" look. Backgrounds are flat cool whites or flat deep slate, at most one very subtle 2-stop slate gradient on the marketing hero.
- **Generic Inter + a default system Hebrew fallback** — looks unfinished and makes the RTL story feel bolted on. Commit to Geist + Heebo as a deliberate bilingual pairing.
- **Over-animation** — bouncy springs, parallax, confetti. One breathing orb, fast ease-out everywhere else.
- **Centered everything / hero with three identical feature cards and a gradient CTA** — the default landing-page template. Use asymmetry, whitespace, and the real product HUD as the hero image.

---

### Files / artifacts to hand the implementer
- Ship tokens as **two files with identical names**: `Frostpane.css` (`:root` + `@media (prefers-color-scheme: dark)`) and `Frostpane.swift` (a `Color` + `Font` extension). 13 color names, 8 type steps, 3 radii (`8 / 12 / 999`), 2 shadows, 1 motion curve.
- Font assets: Geist + Geist Mono (Latin) + Heebo (Hebrew) as variable `.woff2` for web and `.ttf` registered in the macOS app bundle.

Sources:
- [Geist — Google Fonts](https://fonts.google.com/specimen/Geist) · [vercel/geist-font](https://github.com/vercel/geist-font)
- [Heebo — Google Fonts](https://fonts.google.com/specimen/Heebo) · [OdedEzer/heebo](https://github.com/OdedEzer/heebo) · [Assistant — Google Fonts](https://fonts.google.com/specimen/Assistant) · [googlefonts/rubik](https://github.com/googlefonts/rubik)
- [Best Monospace Fonts 2026 — madegooddesigns](https://madegooddesigns.com/best-monospace-fonts-2026/)
- [Liquid Glass — Apple Developer](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass) · [Build a SwiftUI app with the new design — WWDC25 #323](https://developer.apple.com/videos/play/wwdc2025/323/) · [Liquid Glass best practices — DEV](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [SwiftUI macOS Vibrancy — Ohanaware](https://ohanaware.com/swift/macOSVibrancy.html) · [Using materials with SwiftUI — createwithswift](https://www.createwithswift.com/using-materials-with-swiftui/) · [ultraThinMaterial — Apple Developer](https://developer.apple.com/documentation/swiftui/shapestyle/ultrathinmaterial)