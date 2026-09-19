# PointPilot

**Which credit card should I use for this purchase?**

PointPilot answers that one question. You tell it the restaurant and roughly what
you'll spend; it compares your cards' category multipliers, merchant offers,
spending caps and airline dining rewards, then recommends the card with the
highest estimated dollar value.

Everything in this app runs on **local sample data**. No bank connection, no real
accounts, no real offers, no purchases. Activation is simulated and labelled as
such throughout the UI.

---

## Two apps, one engine

This repository contains two apps that answer the same question and are meant to
behave identically:

| | Path | Stack | Docs |
|---|---|---|---|
| **iOS app** | `PointPilot/` | SwiftUI, iOS 17+, no dependencies | this file |
| **Website** | `web/` | React + Vite + TypeScript | [`web/README.md`](web/README.md) |

The recommendation logic is **ported, not reimplemented**, and both platforms
are pinned to the same published figures by `web/src/lib/parity.test.ts`. That
suite asserts the web engine produces exactly what the Swift engine does — Nobu
at $200 → Amex Gold **$45.00** over Sapphire Preferred **$19.50**. If a change
on one side makes the two disagree, those tests fail.

The website has **no microphone, no GPS/Yelp and no persistence** — see
[`web/README.md`](web/README.md) for the honest list of gaps.

---

## Requirements (iOS app)

| | |
|---|---|
| **Xcode** | 15.0 or later (developed and verified on Xcode 26.6) |
| **iOS** | 17.0 or later |
| **Swift** | 5.9 or later |
| **Device** | iPhone, portrait |

No third-party dependencies are required to build or run the app.

## Open and run

```bash
open PointPilot.xcodeproj
```

Select the **PointPilot** scheme and any iPhone simulator, then press Run (⌘R).
The app opens on the **Home** screen and is fully functional immediately — no
credentials, no network.

To run the tests: ⌘U, or

```bash
xcodebuild -project PointPilot.xcodeproj -scheme PointPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Regenerating the project

`PointPilot.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated project is
committed so the app opens without extra tooling, but if you add or move source
files, regenerate it:

```bash
brew install xcodegen      # once
xcodegen generate          # in the repo root
```

---

## Demo mode

The app is **always** demonstrable. Recommendations are computed locally by the
`RecommendationEngine` regardless of whether voice is available.

| | Voice configured | Voice not configured (default) |
|---|---|---|
| Voice button | Active | Shown, with a non-blocking notice |
| Recommendation | Local engine | Local engine — identical results |
| Typed input | Always available | Always available |
| Offer activation | Simulated | Simulated |

With no ElevenLabs credentials, the app uses `MockVoiceAgentService`. It is not a
stub: it emits real states, transcripts and a `recommendCard` tool call through
the same `VoiceAgentProviding` boundary the SDK adapter uses, and it parses
sentences like *"I'm at Nobu and spending around $200"* locally. The transcript
says plainly that the voice is simulated.

A visual **"Demo data"** disclosure appears on the recommendation screen and in
the wallet.

---

## Configuring Yelp Fusion API & Environment (.env)

PointPilot integrates with **GPS CoreLocation** and the **Yelp Fusion API** to auto-detect nearby restaurants and populate merchant recommendations with 1 tap.

**The `.env` at the repository root is the single source of truth.** Edit that
one file and nothing else:

```bash
YELP_API_KEY=your_real_yelp_fusion_api_key
```

Then run `xcodegen generate` and build.

The app cannot read the repo root directly — `FileManager.currentDirectoryPath`
is `/` inside a running app, and a sandboxed iOS app cannot open files outside
its own container. So the `Bundle .env` pre-build script copies the keys the app
reads into the app bundle at build time, which is what makes that path work.

Two deliberate constraints on that script:

- **It whitelists keys** (`YELP_API_KEY`, `YELP_TOKEN`, `ELEVENLABS_AGENT_ID`).
  Everything else in `.env` stays out of the binary. That matters most for an
  ElevenLabs API key, which is a server-side secret: anything shipped in the app
  can be extracted from it, so an API key must never be copied in.
- It needs `ENABLE_USER_SCRIPT_SANDBOXING: NO`, because it reads a file outside
  the script sandbox's permitted roots.

With no key present, the app falls back to offline sample dining venues.

**Verified behaviour, measured on a running app:** the root `.env` loads
(`isYelpConfigured == true`, 128-char key) and the bundled copy contains only
`YELP_API_KEY`.

> **Security Mandate**: `.env` and `*.env` files are included in `.gitignore` and are **never** committed to version control.

### When Yelp returns nothing

`YelpFusionService` still falls back to bundled sample venues on any non-200
response, so the app never dead-ends — but the fallback is no longer silent. It
reports a `MerchantSource`, and the Ask screen discloses it:

> Showing sample venues — live Yelp results unavailable.

That notice appears only after a real lookup fails, so launch stays quiet and
successful live results carry no caveat. This matters because a rejected key, an
expired trial, a timeout and "nothing nearby" all otherwise look identical —
the chips populate either way. Three tests pin it: a simulated `TRIAL_EXPIRED`
response reports `.sample`, a successful response reports `.live`, and no
disclosure appears before any attempt.

Check the key against Yelp directly before assuming a wiring problem:

```bash
curl -H "Authorization: Bearer $YELP_API_KEY" \
  "https://api.yelp.com/v3/businesses/search?latitude=40.7128&longitude=-74.0060&limit=1"
```

A `400` here (e.g. `TRIAL_EXPIRED`) means the key is the problem, not the app.

---

## Configuring ElevenLabs safely

**No API key or agent secret is ever committed.** Only a *public agent ID* is
used, and it is read at runtime from a gitignored plist. If it is missing or
still holds placeholders, the app runs in demo mode.

The ElevenLabs Swift SDK (`elevenlabs-swift-sdk`, 3.3.1+) is already declared as
a package dependency in `project.yml`, so no manual Xcode step is needed — run
`xcodegen generate` and the package resolves on the next build.

> **Never put an ElevenLabs API key in this app.** The API key is a server-side
> secret and anything compiled into a binary can be extracted from it. The app
> needs only the public agent ID. For a private agent, mint a conversation token
> on a backend and use the SDK's `conversationToken:` overload.

1. Copy the example config to the gitignored path and fill in your agent ID:

   ```bash
   cp Config/ElevenLabs.example.plist PointPilot/Config/ElevenLabs.plist
   ```

2. Configure your agent in the ElevenLabs dashboard with a **client** tool named
   `recommendCard` accepting `merchant` (string) and `amount` (number).
3. Run `xcodegen generate`, then build. `ElevenLabsVoiceAgentService` is compiled
   only when the SDK is present (`#if canImport(ElevenLabs)`), so the project
   builds with or without it.

Like the env file, the plist must sit inside `PointPilot/` to be bundled. The app
prefers `ELEVENLABS_AGENT_ID` from a bundled env file and falls back to the
plist, so either works.

### The agent's contract

The conversational agent is deliberately constrained:

- It **asks** for the merchant if missing, and the amount if missing.
- It **calls** `recommendCard(merchant, amount, category)` rather than doing
  arithmetic itself.
- It **speaks only** figures the recommendation engine returns.
- It **asks for confirmation** before simulating offer activation.
- It **never claims** a payment or a real activation occurred.

The system prompt that enforces this is documented in
[`ElevenLabsAgentPrompt.md`](ElevenLabsAgentPrompt.md).

---

## Architecture

```
PointPilot/
├── Models/          CreditCard, Merchant, CardOffer, DiningProgram,
│                    RewardCategory, RewardComponent, Currency,
│                    HistoryEntry, MetricsSummary
├── Engine/          RecommendationEngine, CardRecommendation,
│                    RecommendationProviding
├── Data/            SampleDataRepository  ← the single source of sample data
├── Voice/           VoiceAgentProviding, MockVoiceAgentService,
│                    ElevenLabsVoiceAgentService, ElevenLabsConfiguration
└── Views/           RootView, HomeView, AskView, RecommendationView,
                     MetricsView, WalletView, AskViewModel,
                     Theme, Illustration, Delight
```

### Screens

| Screen | Role |
|---|---|
| `HomeView` | The front door: greeting, a hero call to action, "I want to…" rows, earned/missed totals, recent activity. |
| `AskView` | The card finder — voice button, typed fallback, nearby chips, wallet preview. Pushed from Home. |
| `RecommendationView` | The result sheet: winner, comparison, breakdown, simulated activation. |
| `MetricsView` | The rewards dashboard: earned, left on the table, card leaderboard, spend by category, activity. |
| `WalletView` | The read-only wallet sheet. |

`RootView` owns the single `NavigationStack` and the wallet sheet. Screens
pushed onto it deliberately do **not** create their own stacks, and the wallet
sheet is presented in exactly one place — two observers of the same flag would
race to present it.

Three protocols form the integration boundaries:

| Protocol | Role |
|---|---|
| `RecommendationProviding` | The engine. UI and voice both depend on this, not on `RecommendationEngine`. |
| `VoiceAgentProviding` | The voice agent. Swappable between the mock and the ElevenLabs SDK. |
| `MerchantProviding` | Merchants and offers. Lets tests run against fixtures. |

**The engine is pure.** It holds no mutable state, performs no I/O and depends on
nothing outside the model layer. Same inputs always produce the same output —
which is what makes it independently testable, and why the voice agent can be
trusted to speak its output.

**One data source.** Every card, merchant and offer lives in
`SampleDataRepository`. No view defines its own copy.

### Value calculation

For each card the engine computes:

```
base reward value + merchant offer value + dining-program value − cap adjustments − fees
```

The Nobu / $200 demo scenario, for the Amex Gold:

| Component | Calculation | Value |
|---|---|---|
| Card rewards | 4× points × 200 × $0.02 | $16.00 |
| Merchant offer | 10% back, advertised | $20.00 |
| Airline dining rewards | 3 miles × 200 × $0.015 | $9.00 |
| **Total** | | **$45.00** |

The Chase Sapphire Preferred scores $19.50 (3× points = $10.50 + $9.00 dining), so
the Amex Gold wins by **$25.50**.

When an offer exceeds its cap, the cap appears as its own negative line rather
than being silently folded in, so the advertised offer stays visible and the
arithmetic still balances. A 10% offer on a $500 Nobu bill shows:

```
Card rewards            +$40.00
Merchant offer          +$50.00
Offer cap adjustment    −$30.00   (capped at $20.00)
Airline dining rewards   +$9.00
Total                    $69.00
```

Components are rounded to cents individually, then summed — so the lines a user
reads always add up to the total they read. This is asserted by a test.

**Money never touches floating point.** All currency is `Decimal`, rounded with
`NSDecimalRound` at `.plain`.

**Ties are deterministic.** Ranking falls back to wallet priority, then card id,
so results never depend on input ordering.

**Unknown merchants invent nothing.** The engine falls back to the dining
category with no merchant offer and no dining-program credit, and says so.

---

## Tests

**70 tests, all passing**: 54 unit tests (engine, voice transcript, Yelp Fusion DTOs, .env parser, Location, discovery, typed voice input) and 16 UI tests (11 for the end-to-end demo flow, 5 for the home screen and rewards dashboard).

### Unit tests (`PointPilotTests/`)
- `RecommendationEngineTests.swift`: 23 tests covering all 8 core math cases, sub-cent rate precision, tie-breaking, and capped adjustments.
- `VoiceTranscriptTests.swift`: 10 tests for state deduplication, newest-first ordering, duplicate suppression, and local-timezone timestamps.
- `AppEnvironmentTests.swift`: 3 tests for .env key-value parsing, comments, and placeholder sanitization.
- `YelpFusionServiceTests.swift`: 6 tests for Yelp API DTO mapping, category inference, offline fallback, and — via a stubbed `URLSessionProtocol` — that a rejected key is reported as sample data while a 200 is reported as live, plus the request the app sends (bearer token, coordinates, `sort_by=distance`).
- `LocationAndDiscoveryTests.swift`: 12 tests for on-demand GPS, one-tap chip selection, the no-location-fix fallback, the denied/restricted/error explanations the UI now shows, typed input to the voice agent, and the timing of the sample-source disclosure.

### UI tests (`PointPilotUITests/`)
- `DemoFlowUITests.swift` — 11 tests driving the real app: typed input, nearby merchant chips, breakdown expansion, capped offer adjustments, simulated activation, wallet sheet, error banners, screen resets, repeated microphone taps, and transcript timestamps.
- `HomeAndMetricsUITests.swift` — 5 tests for the two screens the redesign added: the app opening on Home rather than the finder, the earned/missed totals, the dashboard's headline sections, its demo-data disclosure, and opening the wallet from Home.

```
Executed 54 tests, with 0 failures     (unit)
Executed 16 tests, with 0 failures     (UI)
Total: 70 tests passing
```

### Voice transcript behavior

- **Repeated microphone taps do not duplicate the greeting.** `MockVoiceAgentService.start()`
  ignores a call while a session is already live, and the second tap ends the
  session instead. The view model also suppresses consecutive identical lines.
- **State changes are deduplicated.** Only a genuinely different `VoiceState` is
  published, so unchanged states never re-render the UI or re-announce via
  VoiceOver.
- **History reads newest-first.** `messages` is ordered latest-to-earliest and
  the view renders from the top, so the most recent exchange is always visible
  without scrolling.
- **Timestamps are local.** Each line carries a `Date` rendered with the
  device's locale and current timezone — no timezone is pinned.

### Location permission behavior

Location is requested **only** when the user taps the "Nearby" button — never on
launch. Gating this behind an explicit action is asserted by
`testLoadingDefaultMerchantsDoesNotRequestLocationPermission`, so the system
permission dialog can never greet the user before they have asked for anything.

If no location fix is available (permission denied, or the device cannot
determine a position), the app keeps the local sample venues and does **not**
query the merchant service with substitute coordinates — presenting unrelated
restaurants as "nearby" would be worse than showing nothing new. This is
asserted by `testLocationFailureKeepsLocalMerchantsAndInventNothing`.

---

## Known MVP limitations

- **Sample data only.** Three cards, nine merchants. No real issuer data.
- **Activation is simulated.** The button and the agent both say so; nothing is
  activated with any issuer.
- **Wallet is read-only.** Cards cannot be added, edited or removed.
- **Merchant offers exist only for dining.** Groceries, travel, gas, shopping and
  entertainment merchants are present and are scored on their category
  multipliers, but no card offer is attached to them.
- **The dashboard's history is a fixed demo aggregate, not your usage.** It is
  replayed through the real `RecommendationEngine` at launch, so its figures are
  the engine's own output — but it does not record what you actually did in the
  app. There is no persistence layer. Purchases tracked span a 30-day window.
- **Annual fees are excluded from per-purchase value by default.** Charging a
  full annual fee against a single transaction would make every card look
  unprofitable and does not reflect the decision being made at the register.
  `RecommendationEngine(includeAnnualFeeInValue:)` supports turning it on.
- **The mock voice parser is simple pattern matching**, not NLU. It handles the
  demo phrasing and common variants. It is a fallback, and typed input is the
  reliable path.
- **ElevenLabs requires a public agent ID and the SDK added manually.** Token
  minting via a backend is the production approach and is out of scope here; the
  adapter documents the wiring point.
- **Point and mile valuations are assumptions**, not market rates.

---

## 60-second demo script

1. **Launch PointPilot.** The Home screen greets you, shows what you've earned
   and what you left on the table, and offers one obvious next action.
2. **Tap "Find my best card."** The card finder opens with nearby restaurants as
   one-tap chips (e.g. Nobu, Shake Shack) alongside the large voice button. GPS
   is requested only if you tap "Nearby" — never on launch.
3. **Tap a nearby chip (or tap the voice button).**
   - If tapping **Nobu**: auto-populates the restaurant name. Type `200` in amount.
   - If speaking: say *"I'm at Nobu and spending around $200."*
4. **The Amex Gold card appears** with a success haptic, a count-up to
   **$45.00**, and a dining illustration matching the purchase category.
5. **The agent speaks the recommendation**, using only the engine's figures.
6. **Tap "See the math."** The breakdown expands: $16.00 rewards, $20.00 offer,
   $9.00 airline dining — totalling $45.00.
7. **Point at "How the others compare":** Sapphire Preferred $19.50, Capital One
   Venture $13.00 — the Amex wins by **$25.50**.
8. **Tap "Activate Offer."** It becomes *Activated (simulated)*, and the screen
   states that nothing was activated with the issuer.
9. **Tap "Ask Another,"** then go back to Home and open **"See my rewards."**
   The dashboard totals are computed by the same engine, so its figures always
   agree with the ones you just saw.

> **Note on the headline number.** The original brief's example totalled $21.40
> from $16.00 + $20.00 + $5.40, which does not sum correctly. The engine is
> additive and self-consistent, so the real figures for a $200 Nobu bill are
> **$45.00** (Amex Gold) over **$19.50** (Sapphire Preferred). The README and the
> tests reflect the engine's actual output rather than the illustrative numbers.

---

## Accessibility

- VoiceOver labels on every card, component, control and comparison row.
- Value is never communicated by colour alone — deductions carry an explicit `−`
  sign and a label; the winner is named, not just highlighted. On the dashboard,
  bars always carry their amount in text and ranks are stated numerically.
- **Illustrations are drawn, not shipped.** Every visual is composed from shapes
  and gradients in `Illustration.swift` — so it stays crisp at any size, follows
  Dark Mode, and adds nothing to the bundle. They are decorative and hidden from
  VoiceOver.
- **The counted-up total is never spoken mid-animation.** The visible figure
  animates, but its accessibility label is pinned to the final amount.
- **Motion respects Reduce Motion.** Springs, count-ups and bar growth are
  suppressed when the system asks for it.
- Full Dynamic Type support, including at accessibility sizes (the voice button
  scales down so it never crowds out the text fields).
- Automatic Dark Mode via semantic system colours.
- Every control meets the 44pt minimum touch target.
- Typed input is a complete, equal alternative to voice.
