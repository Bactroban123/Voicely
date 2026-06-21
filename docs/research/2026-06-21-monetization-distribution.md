# Research: monetization-distribution

I now have decision-grade coverage across all five sub-domains. I have the key 2026 facts: Stripe acquired Lemon Squeezy (slowing), Polar.sh is the indie-favorite MoR with native license keys at 5%+50¢, Azure Artifact Signing at $9.99/mo, Microsoft Store individual registration now free, Apple Small Business Program 15%, RevenueCat free under $2.5K MTR, Velopack for Windows, Sparkle for macOS, and the iOS keyboard-extension architecture that Wispr Flow uses. Let me compile the final report.

---

# Voicely — Distribution & Monetization Playbook (June 2026)

This is the "take a credit card + install on every platform" plan. Bottom line up front: sell via **Polar.sh** (merchant-of-record with native license keys), distribute macOS direct (Developer ID + notarization + Sparkle), put iOS/Android in the stores billed by **RevenueCat**, and ship Windows with **Velopack** signed by **Azure Artifact Signing**.

---

## 1. The monetization decision (model + price + stack)

### Recommended pricing model

Voicely's whole moat vs. Wispr Flow is **on-device, offline, private**. That kills the metered cloud-cost story that forces Wispr into pure subscription — Voicely's marginal cost per word is ~$0 (Whisper/Parakeet run locally; only OpenRouter cleanup costs money, and that's small). So you have pricing freedom Wispr doesn't. Use it.

**Recommended: hybrid "subscription OR lifetime", with a real free tier.**

| Tier | Price | What you get |
|---|---|---|
| **Free** | $0 | Unlimited on-device dictation (this is the wedge — Wispr caps free at 2,000 words/week), English+Hebrew transcription, basic insertion. No translation, no AI cleanup, no custom vocab/snippets. |
| **Pro (sub)** | **$8/mo or $60/yr** | Translation (EN↔HE), all 3 AI cleanup modes, custom vocabulary, snippets, priority models. |
| **Pro (lifetime)** | **$99 one-time** | Same Pro features, perpetual, 1 year of updates included (then optional). |

**Why these numbers (2026 market):** Wispr Flow Pro is **$15/mo or $144/yr** ([wisprflow.ai/pricing](https://wisprflow.ai/pricing)); Superwhisper is **$8.49/mo / ~$84 lifetime** and is the offline-private competitor most like you ([weesperneonflow.ai pricing comparison](https://weesperneonflow.ai/en/blog/2026-04-04-ai-dictation-pricing-per-hour-vs-monthly-subscription-2026/)). Undercut Wispr on subscription, match Superwhisper, and add a **lifetime** option Wispr refuses to offer — that's your sharpest differentiator for the privacy-conscious crowd who hate cloud subscriptions. A generous unlimited-free-on-device tier is the single best growth lever against Wispr's word cap.

Mobile note: iOS/Android sell **subscription only** (lifetime/one-time IAP is allowed but Apple/Google still take their cut and it complicates restore). Keep lifetime as a **desktop-direct, license-key** product; offer subscription on mobile via RevenueCat.

### The payments + licensing stack

The core 2026 decision is **merchant-of-record (MoR) vs. raw Stripe + a license server.** An MoR becomes the seller of record and handles **EU VAT / US sales tax / global compliance** for you — essential for a solo/indie seller who can't track tax in 50 jurisdictions. The catch worth knowing: **Stripe acquired Lemon Squeezy (July 2024)** and through 2026 LS development has visibly slowed with indie makers migrating off ([creem.io](https://www.creem.io/blog/lemonsqueezy-alternatives-after-stripe-acquisition), [buildmvpfast](https://www.buildmvpfast.com/blog/lemon-squeezy-vs-polar-paddle-merchant-of-record-2026)). So don't build new on Lemon Squeezy.

**Recommendation — desktop license sales: Polar.sh.** It's the indie-favorite MoR in 2026, **open-source**, and has **native license-key generation + a real validation/activation API** (device activation limits, expiration, usage quotas) — which most MoRs lack.
- Fees: **5% + 50¢** on the free Starter plan; you can buy the rate down with a subscription (Pro $20/mo → 3.8%+40¢, etc.) ([dodopayments Polar review](https://dodopayments.com/blogs/polar-sh-review), [polar.sh/docs MoR](https://polar.sh/docs/merchant-of-record/introduction)).
- License keys: `POLAR_*****` branded keys, with **`/activate`** (register a device instance, get an activation ID) and **`/validate`** endpoints, configurable activation limits, expiration, and usage counters. Customers self-manage activations in the Polar dashboard ([polar.sh license keys docs](https://polar.sh/docs/features/benefits/license-keys)).

**Alternatives, ranked:**
- **Paddle** — most mature MoR, same 5%+50¢, but enterprise-leaning and **no native license keys** (you'd bolt on Keygen). Pick this only if you outgrow Polar ([contracollective](https://contracollective.com/blog/paddle-vs-lemon-squeezy-merchant-of-record-digital-commerce-2026)).
- **Lemon Squeezy** — has license keys but post-Stripe uncertainty; its keys are "just a counter, no device awareness / no offline validation" ([licenseseat](https://licenseseat.com/alternative-to-lemonsqueezy)). Avoid for new builds.
- **Creem / Dodo Payments** — newer indie MoRs, cheaper at low volume; less proven. Reasonable fallbacks ([creem.io](https://www.creem.io/blog/lemonsqueezy-alternatives-after-stripe-acquisition)).
- **Raw Stripe Checkout + a dedicated license server** — only if you want maximum control and will handle tax yourself (or via Stripe Tax). For the license server, use **Keygen**: it's open-source **fair-source (ELv2)**, **self-hostable free** (Community Edition, Docker), purpose-built for desktop apps with **offline/cryptographic license validation** and SDKs for Swift/Rust/C#/Kotlin — the strongest technical licensing layer if you go non-MoR ([github.com/keygen-sh/keygen-api](https://github.com/keygen-sh/keygen-api), [keygen.sh/pricing](https://keygen.sh/pricing/)). Keygen Cloud is also an option (free Dev tier, paid from ~$49–$299/mo by volume).

**Mobile billing: RevenueCat** — non-negotiable for iOS+Android subscriptions. It abstracts StoreKit 2 + Google Play Billing, gives cross-platform entitlements, and is **free up to $2,500/mo tracked revenue, then 1% of MTR** — no minimums ([revenuecat.com/pricing](https://www.revenuecat.com/pricing), [costbench](https://costbench.com/software/subscription-billing/revenuecat/)). You will not regret using it over hand-rolling StoreKit.

**Cleanest end-state:** Polar (desktop license keys + web checkout, handles tax) + RevenueCat (mobile subs). Two systems, both with generous free/low entry cost.

---

## 2. macOS distribution (direct + optional MAS)

You're already self-signed; the upgrade is **Developer ID + notarization** so Gatekeeper opens it with no scary warning.

**What the human must do (one-time):** Join the **Apple Developer Program — $99/yr** ([developer.apple.com](https://developer.apple.com/app-store/review/guidelines/)). Create two certs: **Developer ID Application** and **Developer ID Installer**. Create an **app-specific password** (or an App Store Connect API key) for notarytool.

**Automatable build/release pipeline:**
1. `codesign` the `.app` with Developer ID, **hardened runtime** (`--options runtime`), correct entitlements. All nested code (incl. embedded Sparkle XPCs) must be signed with the same identity ([sparkle-project notarization notes](https://sparkle-project.org/documentation/), [steipete.me code signing](https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears)).
2. Build a **DMG** — use **[create-dmg](https://github.com/create-dmg/create-dmg)** (the `sindresorhus/create-dmg` or `create-dmg/create-dmg` repos) for a styled drag-to-Applications window.
3. **Notarize**: `xcrun notarytool submit Voicely.dmg --keychain-profile "VOICELY" --wait` (notarytool replaced altool).
4. **Staple**: `xcrun stapler staple Voicely.dmg` so it validates offline ([scriptingosx notarytool guide](https://scriptingosx.com/2021/07/notarize-a-command-line-tool-with-notarytool/)).

**Auto-update: Sparkle 2** — the standard for non-MAS Mac apps. Embed Sparkle, generate an **EdDSA (ed25519) keypair** once (`generate_keys`), keep the private key in CI, ship the public key in the app, and publish an **appcast.xml** pointing at your notarized DMGs. Sparkle's `generate_appcast` tool signs each build ([sparkle-project docs](https://sparkle-project.org/documentation/), [github.com/sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle)). Host the appcast + DMGs on any static host (Polar can host downloads, or GitHub Releases / Cloudflare R2).

**Mac App Store vs. direct:**
- **Direct (recommended primary)** keeps your global hotkey (CGEventTap), Accessibility text insertion, and clipboard paste — which **MAS sandboxing fights hard** (Accessibility + global event taps are notoriously rejected/limited in the sandbox). Direct also means **0% Apple commission** — you only pay Polar's ~5%.
- **MAS (optional secondary)** buys discovery + trusted billing, but Apple takes **15%** under the **App Store Small Business Program** (auto-eligible under $1M/yr) vs 30% standard. Worth a sandbox-compatible "lite" build later, not at launch.
- **Setapp** — a third channel: subscription bundle ($/mo to users, you get a revenue share by usage). Good for incremental reach once you have traction; submit after direct + stores are live ([setapp.com](https://setapp.com/app-reviews/best-mac-app-store-alternative)).

---

## 3. iOS / Android

**Architecture reality (study Wispr Flow's shipped app):** the way these dictation apps work on iOS is a **custom keyboard extension** + the main app. The keyboard's "Start Flow" button bounces to the main app to run the mic session (keyboard extensions have tight memory/mic limits), then returns you to the field and types the result ([9to5mac on Wispr](https://9to5mac.com/2025/06/30/wispr-flow-is-an-ai-that-transcribes-what-you-say-right-from-the-iphone-keyboard/), [Swift Forums thread](https://forums.swift.org/t/how-do-voice-dictation-keyboard-apps-like-wispr-flow-return-users-to-the-previous-app-automatically/83988)). Your **offline on-device** model is a genuine edge here — Wispr's keyboard **fails with no internet**; Superwhisper runs fully on-device and markets exactly that. Build for on-device first.

**iOS requirements & review gotchas:**
- Apple Developer Program ($99/yr, shared with macOS).
- **Custom keyboard rules (Guideline 4.4 / privacy):** the keyboard must provide basic function **without "Full Access"**; only request Full Access (network) when needed and **disclose it clearly**. Filter/moderate any user content. App Privacy labels must precisely declare data use ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [fleksy.com keyboard limits](https://www.fleksy.com/blog/limitations-of-custom-keyboards-on-ios/)). Your privacy story (on-device, no upload) is a review *asset* — say it loudly in the listing and labels.
- Subscriptions **must** use Apple IAP (RevenueCat wraps StoreKit 2). Don't link out to web checkout for the digital subscription (anti-steering rules still bite).

**Android:** Google Play Developer account (**$25 one-time**). Same keyboard (IME) model. RevenueCat wraps Google Play Billing. Android is laxer about IMEs/network than iOS.

**Mobile billing:** **RevenueCat** for both, with cross-platform entitlements so a Pro user is Pro everywhere. Sample repos: [github.com/RevenueCat/purchases-ios](https://github.com/RevenueCat/purchases-ios) and [purchases-android](https://github.com/RevenueCat/purchases-android).

---

## 4. Windows

**Code signing — the cheap 2026 win: Azure Artifact Signing** (formerly Trusted Signing). **$9.99/mo**, no hardware token, no $300–600/yr EV cert. It produces SmartScreen-trusted signatures. **Caveat: individual developers are currently US/Canada only** (orgs broader), and it needs a **paid** Azure subscription (no free tier) and does **not** do EV / driver signing ([azure.microsoft.com/pricing/artifact-signing](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/), [techcommunity individual signup](https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-is-now-open-for-individual-developers-to-sign-up-in-public-previ/4273554), [melatonin.dev guide](https://melatonin.dev/blog/code-signing-on-windows-with-azure-trusted-signing/)). If you're outside US/CA as an individual, fall back to a standard OV cert via your org entity, or an EV/cloud cert (~$200–550/yr, [ssl2buy](https://www.ssl2buy.com/azure-key-vault-code-signing-certificate.php)).

**Installer + auto-update: Velopack.** It's the **successor to Squirrel.Windows**, written in Rust, does **installer + delta auto-updates**, is cross-platform (Win/macOS/Linux), and **auto-migrates** existing Squirrel apps. This is the modern pick over raw Squirrel ([github.com/velopack/velopack](https://github.com/velopack/velopack), [velopack.io](https://velopack.io/)). For a plain installer with no updater, **Inno Setup** is the simplest, most accessible option (Pascal scripting, free); NSIS is more customizable but harder. Velopack covers both packaging and update, so prefer it.

**Distribution channels:**
- **Direct download** (signed Velopack installer on your site) — primary.
- **winget** — submit a manifest to the community repo so users can `winget install Voicely`; free, no store account needed ([learn.microsoft.com winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/)).
- **Microsoft Store** — **as of 2026, individual developer registration is FREE** (Microsoft dropped the ~$19 fee, ~200 markets) and **company accounts are now free too** (May 2026). Easy reach, low effort ([learn.microsoft.com individual dev](https://learn.microsoft.com/en-us/windows/apps/publish/whats-new-individual-developer), [Windows Dev Blog May 2026](https://blogs.windows.com/windowsdeveloper/2026/05/07/publish-to-microsoft-store-as-a-company-now-with-free-registration-and-faster-onboarding/)).

---

## 5. Marketing/landing + checkout site

**Stack: Next.js (App Router) on Vercel + Polar checkout.** You already run exactly this stack on Collabo, so reuse it.
- Landing page in Next.js, deployed on Vercel.
- "Buy" button → **Polar Checkout** (hosted, MoR handles tax) → on success, Polar emails the license key and fires a **webhook**; your tiny Next.js route handler stores the license + emails the DMG/installer links. Polar has a first-party Next.js SDK and webhook examples ([polar.sh/docs](https://polar.sh/docs/merchant-of-record/introduction)).
- If you instead go raw Stripe: use **Stripe Checkout + a webhook → Keygen** to mint a key (templates: [github.com/keygen-sh](https://github.com/keygen-sh) examples + Stripe's `checkout.session.completed` webhook). But for a solo seller, Polar's bundled tax + license keys is less code and less liability.
- Auto-update hosting: serve the **Sparkle appcast** (macOS) and **Velopack feed** (Windows) from Vercel static / R2 / GitHub Releases.

---

## Step-by-step "path to first paid download"

**macOS (fastest revenue — do this first):**
1. [Human] Buy Apple Developer Program ($99/yr); create Developer ID Application + Installer certs; make an app-specific password.
2. [Auto] CI: codesign (hardened runtime) → create-dmg → `notarytool submit --wait` → `stapler staple`.
3. [Auto] Embed Sparkle 2, generate EdDSA keys, publish appcast.
4. [Human] Create Polar account + a "Voicely Pro" product with license-key benefit (lifetime $99 + monthly/annual sub).
5. [Auto] Next.js landing on Vercel with Polar Checkout + webhook that gates Pro features on a valid Polar license (`/validate`). **→ First paid download.**

**Windows (parallel):**
1. [Human] Azure paid subscription + Azure Artifact Signing ($9.99/mo) **or** an OV cert if outside US/CA.
2. [Auto] Build with Velopack (installer + delta updater), sign with the Azure cert.
3. [Human] Free Microsoft Store account + submit; [Auto] submit winget manifest; host direct download. Reuse the same Polar license check.

**iOS:**
1. [Human] Same $99 Apple account; build the keyboard-extension + main app (on-device Whisper/Parakeet).
2. [Human] RevenueCat account; configure subscription products in App Store Connect; wire RevenueCat SDK.
3. [Human] Submit; nail the **keyboard Full-Access disclosure + privacy labels** (lead with "on-device, nothing uploaded"). **→ First mobile subscriber.**

**Android:**
1. [Human] Google Play account ($25 one-time); build IME + app.
2. [Auto/Human] RevenueCat + Google Play Billing; submit. Laxer review.

**What requires the human:** every developer-account signup, every payment/identity verification, every cert issuance, and store submissions (Apple/Google/MS review). **What's automatable:** all signing, notarization, DMG/installer builds, appcast/feed generation, webhook-to-license plumbing, and CI release.

**Cheapest credible setup:** Apple $99/yr + Google $25 once + Azure Artifact Signing $9.99/mo + Microsoft Store free + winget free + Polar 5%+50¢ (no fixed fee) + RevenueCat free under $2.5K/mo + Vercel free/hobby. Effective fixed cost ≈ **$99/yr + ~$10/mo**, everything else is revenue-share that scales only when you're earning.

---

**Sources:**
- [wisprflow.ai/pricing](https://wisprflow.ai/pricing) · [AI dictation pricing 2026 (Weesper)](https://weesperneonflow.ai/en/blog/2026-04-04-ai-dictation-pricing-per-hour-vs-monthly-subscription-2026/)
- [Polar MoR docs](https://polar.sh/docs/merchant-of-record/introduction) · [Polar license keys](https://polar.sh/docs/features/benefits/license-keys) · [Polar pricing review (Dodo)](https://dodopayments.com/blogs/polar-sh-review)
- [LemonSqueezy post-Stripe alternatives (Creem)](https://www.creem.io/blog/lemonsqueezy-alternatives-after-stripe-acquisition) · [Paddle vs LS (Contra)](https://contracollective.com/blog/paddle-vs-lemon-squeezy-merchant-of-record-digital-commerce-2026)
- [Keygen API (GitHub)](https://github.com/keygen-sh/keygen-api) · [Keygen pricing](https://keygen.sh/pricing/)
- [RevenueCat pricing](https://www.revenuecat.com/pricing) · [RevenueCat 2026 cost (Costbench)](https://costbench.com/software/subscription-billing/revenuecat/)
- [Sparkle docs](https://sparkle-project.org/documentation/) · [Sparkle GitHub](https://github.com/sparkle-project/Sparkle) · [Code signing & notarization (steipete)](https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears) · [notarytool guide](https://scriptingosx.com/2021/07/notarize-a-command-line-tool-with-notarytool/)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [iOS keyboard limits (Fleksy)](https://www.fleksy.com/blog/limitations-of-custom-keyboards-on-ios/) · [Wispr keyboard mechanics (9to5Mac)](https://9to5mac.com/2025/06/30/wispr-flow-is-an-ai-that-transcribes-what-you-say-right-from-the-iphone-keyboard/) · [Setapp alternatives](https://setapp.com/app-reviews/best-mac-app-store-alternative)
- [Velopack (GitHub)](https://github.com/velopack/velopack) · [Velopack.io](https://velopack.io/)
- [Azure Artifact Signing pricing](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/) · [Individual dev signup (Microsoft)](https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-is-now-open-for-individual-developers-to-sign-up-in-public-previ/4273554) · [Code signing with Azure (Melatonin)](https://melatonin.dev/blog/code-signing-on-windows-with-azure-trusted-signing/)
- [Microsoft Store free individual registration](https://learn.microsoft.com/en-us/windows/apps/publish/whats-new-individual-developer) · [Windows Dev Blog (May 2026)](https://blogs.windows.com/windowsdeveloper/2026/05/07/publish-to-microsoft-store-as-a-company-now-with-free-registration-and-faster-onboarding/) · [winget docs](https://learn.microsoft.com/en-us/windows/package-manager/winget/)