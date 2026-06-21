# Voicely — Product Context

**Register:** product (a tool; design serves the task and disappears into it).

## What it is
A personal, native macOS menu-bar dictation app. Press a configurable hotkey, speak, and on-device-transcribed + AI-cleaned text lands at the cursor in any app. Single-user, not for sale.

## Who uses it
One person (the builder) — a fast-moving founder/developer who dictates into Slack, Notes, browsers, and a code editor all day, on an Apple M3 Pro. Fluent in great tools (Raycast, Linear, Superwhisper). Wants speed and trust, not features.

## Tone
Quiet, native, exact. The app should feel like it shipped from Cupertino: no novelty, no chrome, no marketing voice. Microcopy is plain and short ("Listening", "Cleaning up…", "Copied · ⌘V to paste").

## Strategic principles
1. Invisible until summoned — no main window, no dock icon.
2. On-device by default — audio never leaves the Mac.
3. Fast enough to trust — under ~1.5 s from key-release to inserted text.
4. Never lose a transcript — every failure path falls back to "it's on your clipboard."

## Anti-references (what it must NOT be)
- A SaaS dashboard with hero metrics and cards.
- A Siri-blue / purple-gradient "AI voice" cliché.
- A file/meeting transcription studio (that's MacWhisper's lane).
- Anything that needs a manual or an onboarding tour beyond granting permissions.

See [docs/specs/2026-06-21-voicely-design.md](docs/specs/2026-06-21-voicely-design.md) for architecture and [DESIGN.md](DESIGN.md) for visual tokens.
