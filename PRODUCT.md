# Voicely — Product Context

**Register:** product (a tool; design serves the task and disappears into it).

## What it is
**The private, bilingual dictation app for people who think in two languages.** A
native macOS menu-bar app (with iOS/Windows/Android planned): press a configurable
hotkey, speak in English or Hebrew, and on-device-transcribed, AI-cleaned, optionally
**translated** text lands at your cursor in any app. Audio never leaves the device.
A commercial product (free unlimited dictation; Pro = translation, cleanup, vocab,
snippets).

## Who it's for
People who live between two languages — Israelis and the Hebrew diaspora first, then
anyone bilingual — plus privacy-conscious power users and developers who dictate into
code ("vibe coding"). They've tried Wispr Flow and dislike that it ships their screen
to the cloud.

## Positioning
> Speak any language. Type it in another. Privately, on your device.

The market split into "cloud + AI" (Wispr, Willow, Aqua) and "on-device + privacy"
(Superwhisper, MacWhisper). **Nobody owns both at once, and nobody does system-wide
English⇄Hebrew.** Voicely owns that intersection.

### Killer differentiators (vs Wispr Flow)
1. **Truly on-device, truly private** — audio never leaves the Mac (Wispr screenshots your screen to its servers).
2. **English ⇄ Hebrew translation** — no other system-wide dictation app does it.
3. **Best-in-class Hebrew** (ivrit.ai models, planned).
4. **Native, not Electron** — a few MB of RAM, won't freeze your editor; offline-reliable.

## Tone
Quiet, native, exact, intellectual. Feels like it shipped from Cupertino. Microcopy is
plain and short ("Listening", "Cleaning up…", "Copied · ⌘V to paste"). Marketing copy is
sharp and confident, never hypey. No em dashes. Bilingual by design (Hebrew is RTL, first-class).

## Strategic principles
1. Invisible until summoned — no main window, no dock icon.
2. On-device by default — audio never leaves the device.
3. Fast enough to trust — under ~1.5 s from key-release to inserted text.
4. Never lose a transcript — every failure path falls back to "it's on your clipboard."
5. Privacy is the product, not a setting.

## Anti-references (what it must NOT be)
- A SaaS dashboard with hero metrics and identical feature cards.
- A Siri-blue / purple-gradient "AI voice" cliché (we're icy "Frostpane", see DESIGN.md).
- A cloud service wearing a native-app costume (that's Wispr).
- A file/meeting transcription studio (that's MacWhisper's lane).

See [docs/plans/2026-06-21-voicely-master-strategy.md](docs/plans/2026-06-21-voicely-master-strategy.md)
for the commercial plan, [docs/STATUS.md](docs/STATUS.md) for what's built vs pending, and
[DESIGN.md](DESIGN.md) for the icy visual system.
