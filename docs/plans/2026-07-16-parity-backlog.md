# M1.5 — Parity backlog (decision document)

Produced 2026-07-16 by a 4-lens research sweep (Wispr Flow itself · OSS peers VoiceInk/Handy/Whispering · meeting-notes reference · in-repo audit) plus a completeness critic. 49 candidate items → deduped and ranked below. **Nothing here is committed work** — it's for Gal to pick from.

Confidence is marked. Where a claim couldn't be verified it says so; don't treat unverified items as facts.

---

## Already fixed during this checkpoint (not backlog)

The research found bugs, not just gaps. Two silent data-loss paths were fixed immediately (`51c5281`, `e8ab96e`) because they belong to M1's charter, not a backlog:

1. **Truncated cleanup pasted as if complete** — `max_tokens` was pinned at 400 (~300 words). Longer dictations were cut mid-sentence, returned HTTP 200, so the raw fallback never fired. Worst for Prompt mode, i.e. long prompts into Claude Code.
2. **Paste into a secure-input terminal destroyed the text** — `postCommandV()` reported success if the events merely *constructed*. With Terminal/iTerm "Secure Keyboard Entry" on, macOS discards synthetic events; the paste never landed, copy-only never fired, and the restore then wiped the clipboard. Dictation gone, no error.

Both were the same shape as the crash bugs M1 fixed: the failure path never fired. **Stabilization closed the crash class; this closed the silent class.**

---

## P0 — do next (all small; mostly activating what's already built)

| # | Item | User value | Effort |
|---|---|---|---|
| 1 | **Streaming cleanup → HUD** | Text assembles live instead of a static "Transcribing…" | S |
| 2 | **History search UI** | Find any past dictation by typing a word from it | S |
| 3 | **Backtrack + filler removal** in cleanup prompts | "2… actually 3" → only "3" survives; ums vanish | S |
| 4 | **Cleanup strength dial + undo to raw** | Choose how hard AI rewrites you; one click shows what you said | S |
| 5 | **Configurable clipboard restore delay** | Fixes "my old clipboard pasted instead of what I said" | S |
| 6 | **Permission-revoked recovery** | Voicely says so and offers the fix instead of going quietly dead | S |

**Why these first:** 1 and 2 are pure dead-code activation — `SSEParser` is built and tested but unused (`CleanupService` hardcodes `stream:false`), and `History.search()` has zero callers, so 188 of your 200 stored transcripts are unreachable (the menu shows only 12). 3 is prompt engineering inside the existing `CleanupModes.system()` and is the best value-per-effort on the list — it's what makes Wispr feel magic versus a raw transcriber. 5 is one hardcoded constant (`restoreDelay = 0.25`); Handy's most-commented open bug is exactly this.

Scope note on 1: **HUD only.** Paste-as-it-arrives needs AX, or it fires a Cmd-V per delta and shreds the target app's undo stack.

## P1 — soon

| Item | User value | Effort |
|---|---|---|
| **App-aware auto mode** (per-app modes) | Prompt mode in Claude Code, Clean in Mail — no menu round-trip | M |
| **User-defined cleanup modes** | Your own named modes and prompts, not 7 baked into the binary | M |
| **Local / OpenAI-compatible cleanup endpoint** | Point cleanup at Ollama — offline, no key, no per-token cost | S |
| **Dev mode — code-aware vocabulary** | camelCase, paths, CLI flags, framework names come out right | M |
| **Context-aware cleanup** (selection + clipboard) | Names and symbols spelled right | S–M |
| **AX direct insertion** | Text lands without touching your clipboard | M |
| **Command Mode / Edit Mode** | Select text, hold hotkey, "make this three bullets" | M–L |
| **Export + erase everything** | Get history out; wipe every trace with one button | S |
| **Hebrew that renders like Hebrew** (RTL + Heebo) | Hebrew reads RTL in HUD/Recent/history | M |
| **Latency budget in Diagnostics** | See what each dictation actually cost | S |

**Notes that change the ranking:**
- **AX is demoted** from where the research first put it. VoiceInk — the leading peer — also pastes via clipboard+Cmd-V and does *not* use AX as its primary path. It's infrastructure (it unblocks Command Mode and real streaming insert), and it misbehaves exactly in Electron apps and terminals — your apps. It needs an allowlist + read-back verification, with clipboard kept as a permanent fallback. **But** the secure-input bug above flips one argument for it: AX doesn't post events, so it isn't blocked by secure input.
- **"Local cleanup endpoint" resolves a strategic contradiction**, not just a gap: today differentiator #2 (EN⇄HE translate) *requires* breaking differentiator #1 (on-device privacy) — the audio stays local, the transcript doesn't. `CleanupService` already speaks the OpenAI shape; this is a base URL and a longer timeout.
- **"A Prompt mode tuned for Claude Code" is not supportable today.** `promptPrompt` is a generic rewriter that knows nothing about file paths or identifiers, and its rules don't even carry the "keep code/URLs unchanged" line the *translate* prompts have.
- **User-defined prompts reopen a closed hole:** Handy shipped "Please provide the transcript…" into users' documents. Voicely's prompt defends against that today; user-authored prompts need question-shaped test utterances shipped alongside.

## P2 — later

Apple Translation framework (on-device EN⇄HE) · mic input device picker · any-hotkey binding (real work is the modifier mask + reworking the tap-vs-hold FSM and its tests, not the picker) · VAD / hands-free auto-stop (FluidAudio already ships Silero) · streaming partial *transcription* (L — distinct from P0 #1 and much bigger) · ivrit.ai Hebrew model (L, unverified — gated on a CT2→CoreML pipeline) · Hebrew UI localization (do RTL *rendering* first; that's the product).

## BLOCKED — needs money, not engineering

| Item | Unblock |
|---|---|
| **Developer ID-signed + notarized build** | **$99/yr Apple Developer ID** |
| **Sparkle auto-update** | Same |

**This is now the first domino for two roadmap items, not one.** It gates Sparkle *and* plausibly all of M2 (process taps may need a signed binary, and the deployment target must rise to ≥14.4 for the right TCC category). Worth a 30-minute ad-hoc spike before spending the $99 — whether ad-hoc suffices for `kTCCServiceAudioCapture` is **unverified**.

Related, found by running the app: `KeychainStore.openRouterKey()` is read synchronously on the main thread at launch, so **launch blocks on a modal Keychain prompt whenever the signature doesn't match the item's ACL** — which is exactly what a Developer ID migration does. Fix it in the same change.

---

## Decisions only Gal can make

1. **Correct or retract the competitive teardown.** Two load-bearing claims don't survive checking. *"Wispr is Electron / freezes editors"* traces entirely to **Windows** sources (Notepad++ is Windows-only — it cannot describe a Mac build). The *"75+ outages / unreliable"* wedge is **stale**: Wispr's own status page shows 99.42% dictation / 100% desktop uptime Apr–Jul 2026. Both originated with competitors selling rival dictation apps. "Native Swift, no Electron" is true and safe *about Voicely*; as a claim *about Wispr's Mac build* it is unverified and costs credibility if challenged.
2. **The privacy wedge is the one that survives — and the defendant documents it.** Wispr's own Context Awareness docs admit collecting screenshots, on-screen text, Slack/Messages history and IDE variable names, sent to their cloud. Lead with that; it needs no competitor sourcing.
3. **The Windows app contradicts the privacy pitch, today.** `windows/app/core.py` POSTs raw microphone audio to OpenRouter (`openai/whisper-1`). It ships from the same `v*` tag as the macOS DMG, so a Voicely-branded product currently uploads user audio to the cloud — while `platforms/README.md` claims `windows/` is "intentionally empty… none is built." Kill it, unlist it, or fix its privacy story. (Out of scope for this program per your macOS-only decision — but it's a live contradiction, not a gap.)
4. **Add a LICENSE.** The repo is formally unmarked (default: all rights reserved). Deps are clean (FluidAudio Apache-2.0, WhisperKit MIT, no copyleft in tree).
5. **Thai scope drift.** Two of seven modes serve a language no strategy doc mentions, while ivrit.ai (differentiator #3) stays unbuilt. Not wrong — but decide it rather than drift into it.
6. **The pixel-monster easter egg occupies the top-level Settings tab slot the strategy assigned to Account/License** — i.e. to the thing that takes money.
7. **Docs are ahead of the code**: `STATUS.md` predates stabilization; master strategy §2 claims AX insertion is done (it isn't); `DESIGN.md` locks Geist/Heebo, RTL, and HUD streaming that don't exist.

---

## M2 reference — meeting notes (informs the planned milestone; not dictation backlog)

Greenfield: verified **zero** meeting-audio code exists.

**The riskiest unknown is now answered.** Two independent peers converged on the same approach: a **Core Audio process tap** (`TapDesc::with_mono_global_tap_excluding_processes(&[])` → `create_process_tap()`) inside a *private* aggregate device. **Not** ScreenCaptureKit, **not** a BlackHole virtual driver. Apple's reference implementation (`insidegui/AudioCap`) is Swift, so Voicely can follow it more directly than the Rust peers did. This matches the approach the approved M2 plan already chose.

**Sequencing:** Developer ID (your call) → capture spike → summarize/notes (parallel, no audio dependency) → the rest.

Licensing: study UX and features only. Several peers are GPLv3 — no code copying.
