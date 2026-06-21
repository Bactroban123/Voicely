# Voicely — Status & Handoff

> Updated June 21 2026, end of the autonomous build session.
> Honest accounting: what's **built + verified**, what's **scaffolded**, and the
> short list of things **only you can do** to start taking credit cards.

---

## TL;DR

Voicely is a **working, beautiful, bilingual, on-device Mac dictation app** with a
**verified icy marketing site** and a **complete commercial master plan**. It is
**not yet a sold, 4-platform product** — that needs accounts/certs only you can
create (Apple $99/yr, Polar) and weeks of platform work (iOS/Windows/Android).
Everything achievable autonomously this session is done and committed.

---

## ✅ Built + verified this session

| Thing | State | How it was verified |
|---|---|---|
| **On-device dictation** (hotkey → transcribe → AI clean → insert) | Working, you use it daily | You confirmed "works great" |
| **EN + Hebrew transcription** (Whisper auto-detect) | Working | Verified on your Mac |
| **EN ⇄ HE translation** (Translate → English / Hebrew modes) | Built, live in the mode switcher | `xcodebuild` + 92 core checks |
| **AI cleanup presets** (Clean / Polish / Prompt) | Working | Verified |
| **Snippets** + **custom vocabulary** (27 terms, 4 snippets from your data) | Working | Loaded + verified |
| **Frostpane icy redesign** (frosted HUD, breathing cyan orb, cyan menu icon) | Built | `xcodebuild` SUCCEEDED |
| **Stable signing** (self-signed cert; permissions survive updates) | Done | Survived 3 reinstalls |
| **Marketing / sales landing page** (`site/index.html`, icy, EN⇄HE demo, 3-tier pricing) | Built | Rendered in browser, 0 console errors |
| **macOS DMG installer** (`scripts/make-dmg.sh` → `dist/Voicely.dmg`) | Built | drag-to-Applications DMG |
| **Master strategy + 6 research reports** | Done | `docs/plans/` + `docs/research/` |
| **VoicelyCore** pure-logic suite | 92 checks green | `swift test` / `verify.sh` |

**The app right now:** menu-bar icon → hold/tap your hotkey → speak EN or HE →
clean text (or translation, or a prompt) lands at your cursor. Switch modes from
the menu-bar "Cleanup mode". Edit vocab/snippets/key in Settings.

---

## 🟡 Scaffolded / planned (not built)

- **Cross-platform apps** — architecture decided + repos identified, scaffolds in
  `platforms/`. iOS reuses Swift/WhisperKit (v2); Windows = Tauri/Rust on the
  [Handy](https://github.com/cjpais/Handy) pattern (v3); Android = Kotlin IME (v3).
  None are built — each is weeks of work (see the roadmap in the master plan).
- **ivrit.ai best-Hebrew model** — planned as a 5th transcription option; needs a
  WhisperKit-compatible CoreML conversion (noted in the plan, not wired, so the
  picker doesn't show a non-functional option).
- **On-device translation** (Apple Translation framework) — the privacy-pure path;
  today translation uses your OpenRouter key (cloud, like Wispr). Plan §3 has the
  exact hidden-NSHostingView implementation for the Apple framework.
- **Live payments / license gating** — the site has pricing + buttons; wiring the
  Polar checkout + license validation needs your Polar account (below).

---

## 🔴 Needs YOU (human-gated — I can't do these)

To go from "great app" to "selling it," in priority order:

1. **Apple Developer Program — $99/yr** (developer.apple.com). Unlocks:
   - A **Developer ID** cert → notarized DMG (double-click-to-open for everyone,
     no right-click dance) + **Sparkle auto-updates**. The release CI in
     `.github/workflows/release.yml` turns this on automatically once the secrets exist.
   - iOS later.
   *This is the single biggest unlock and a hard prerequisite for clean distribution.*
2. **Polar.sh account** (polar.sh) → create a "Voicely Pro" product (lifetime $99 +
   $8/mo·$60/yr). Paste the checkout URLs into `site/index.html` (the `#mac-download`
   buttons). Polar hosts the checkout, so this alone = **taking a credit card**.
3. **Deploy the site** — it's static (`site/`), drop it on Vercel (you have it) or
   any host, point a domain. ~5 minutes.
4. **Confirm the icy redesign** — I overrode the old warm-amber identity for the
   icy "Frostpane" you asked for. If you love it, nothing to do; if not, say so.

**Already handled by you:** OpenRouter key (in the Keychain), Accessibility/Mic
permissions, the stable signing cert.

**Cheapest path to first sale:** Apple $99/yr + Polar (revenue-share only) +
free Vercel = live, paid Mac download. Windows adds ~$10/mo (Azure signing);
Android $25 once; iOS uses the same Apple account.

---

## Run / build / ship

```bash
# the app
./scripts/install.sh                 # build + sign + install to /Applications
open /Applications/Voicely.app

# the installer
./scripts/make-dmg.sh                # → dist/Voicely.dmg

# the site (static)
python3 -m http.server 4321 --directory site   # then open localhost:4321

# the core tests
cd VoicelyCore && swift test         # (or ./scripts/verify.sh without Xcode)
```

**The plan:** [`docs/plans/2026-06-21-voicely-master-strategy.md`](plans/2026-06-21-voicely-master-strategy.md) is the full commercial roadmap. Research backing it is in [`docs/research/`](research/).
