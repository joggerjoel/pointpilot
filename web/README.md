# PointPilot — Web

The website counterpart of the PointPilot iOS app. Same question, same engine,
same sample data, same guarantees:

> **Which credit card should I use for this purchase?**

You give it a restaurant and a rough spend; it compares your cards' category
multipliers, merchant offers, spending caps and airline dining rewards, then
recommends the card with the highest estimated dollar value.

Everything runs on **local sample data** in the browser. No bank connection, no
real accounts, no real offers, no network calls, no API keys. Activation is
simulated and labelled as such throughout the UI.

---

## Requirements

| | |
|---|---|
| **Node** | 18 or later (developed and verified on Node 26.7.0) |
| **npm** | 9 or later |

## Run it

```bash
cd web
npm install
npm run dev          # http://localhost:5173
```

| Script | What it does |
|---|---|
| `npm run dev` | Dev server with hot reload |
| `npm run build` | Typecheck, then produce a production bundle in `dist/` |
| `npm run preview` | Serve the built bundle on port 4173 |
| `npm test` | Run the test suite (Vitest) |

---

## Tests

**42 tests, all passing**, across three files:

| File | Covers |
|---|---|
| `src/lib/parity.test.ts` | 19 tests pinning the engine to the **Swift engine's documented figures** — the contract described below. |
| `src/lib/voice.test.ts` | 11 tests for the agent's state machine, parsing, and the activation confirmation flow (a refusal and an unrecognised reply both leave the offer untouched). |
| `src/App.test.tsx` | 12 integration tests driving the real UI: submitting a purchase, the breakdown, capped offers, the unknown-merchant path, rejected amounts, activation, the dashboard, the wallet, and the voice flow end to end. |

The split mirrors the iOS project: `parity.test.ts` is the counterpart of
`RecommendationEngineTests`, and `App.test.tsx` the counterpart of
`DemoFlowUITests`.

```bash
npm test        # 42 passing
npm run build   # typecheck + production bundle
```

---

## How this mirrors the iOS app

The web app is a **port, not a reimplementation**. The two are meant to behave
identically, and the important parts are structured to make that checkable.

| iOS | Web |
|---|---|
| `Engine/RecommendationEngine.swift` | `src/lib/engine.ts` |
| `Data/SampleDataRepository.swift` | `src/lib/sampleData.ts` |
| `Models/Metrics.swift` + `HistoryEntry` | `src/lib/metrics.ts` |
| `Voice/MockVoiceAgentService.swift` | `src/lib/voice.ts` |
| `Views/HomeView.swift` | `src/views/HomeView.tsx` |
| `Views/AskView.swift` | `src/views/FindCardView.tsx` |
| `Views/MetricsView.swift` | `src/views/MetricsView.tsx` |
| `Views/WalletView.swift` | `src/views/WalletView.tsx` |
| `Views/Illustration.swift` | `src/components/Illustration.tsx` |
| `Views/Delight.swift` | `src/components/CountUpCurrency.tsx` |

### Money is never a float

The Swift engine uses `Decimal` and rounds half-away-from-zero. IEEE floating
point would drift — `3 * 200 * 0.0175` is `10.499999999999998` in binary — so a
naive `toFixed(2)` would print figures that disagree with the phone.

`src/lib/money.ts` therefore holds money as an **integer count of millionths of a
dollar** (micro-dollars). Every rate in the sample data is exact at that scale,
multiplication is integer arithmetic, and rounding matches `NSDecimalRound`'s
`.plain` rule. Floats are used only for layout fractions and final formatting,
never for a total.

### The parity suite is the contract

`src/lib/parity.test.ts` pins this engine to the figures **the Swift engine
produces** — the documented outputs of `RecommendationEngineTests` and the demo
script in the iOS README:

```
Nobu / $200  →  Amex Gold $45.00   ($16.00 + $20.00 + $9.00)
                 runner-up Sapphire Preferred $19.50
                 advantage $25.50
Nobu / $500  →  cap adjustment −$30.00 ("Capped at $20.00")
Unknown      →  $16.00, no offer invented
```

Those expectations are the contract, not a snapshot of whatever the web code
happens to return today. If someone changes the web engine so it disagrees with
the phone, these tests fail.

### The dashboard cannot contradict the finder

The demo history in `src/lib/metrics.ts` is **replayed through the real engine**
at load rather than hand-written. So the dashboard's totals are the engine's own
output for those purchases, and they always agree with what the finder computes
for the same merchant and amount. The iOS app makes the same guarantee, and both
are pinned to `$66.78` earned / `$9.05` missed.

---

## Voice

**Voice is simulated and typed-only in this version.** There is no microphone, no
audio, and no API key.

`src/lib/voice.ts` is not a stub: it runs a real state machine
(`idle → listening → thinking → speaking`), emits real transcript lines, and
parses sentences like *"I'm at Nobu and spending around $200"* into a tool call
through the same `VoiceAgent` boundary a real adapter would implement. The
transcript says plainly that it is simulated.

**Activation goes through the agent.** Saying yes to "Activate this offer?" calls
`onActivationRequest`, and the app owns the resulting state — the agent never
activates anything itself, matching the iOS `VoiceAgentProviding` division.
Activation is never silent: the user confirms first, and an unrecognised reply is
treated as a refusal, because the safe default for a consequential action is not
to take it.

The interface is the seam. Adding real voice means writing a `WebRTCVoiceAgent`
against `VoiceAgent` and swapping it in `App.tsx` — no view changes.

---

## What the website does *not* have

Parity is deliberate but not total, and the gaps are worth stating plainly:

- **No microphone.** See above.
- **No GPS or Yelp.** iOS requests location on demand and queries Yelp Fusion for
  nearby restaurants. The web app shows a fixed sample list of nearby venues
  instead. Adding it would need a backend to hold the Yelp key — shipping it in
  browser code would expose the key.
- **No persistence.** The dashboard history is a fixed demo aggregate, not a
  record of what you did in the app. Neither platform has a storage layer yet.
- **No annual-fee toggle.** Both engines support charging a card's annual fee
  against a purchase (`includeAnnualFeeInValue` in Swift,
  `includeAnnualFeeInValue` in `RecommendationOptions` here), but neither UI
  exposes it. It is off by default in both, since amortizing a full annual fee
  onto one transaction would make every card look unprofitable.
- **No location feedback.** iOS explains a denied or restricted permission on
  screen; the web app has no location feature at all, so it has nothing to
  explain.

---

## Accessibility

- Semantic landmarks, a real `<nav>`, and labelled controls throughout.
- **Value is never carried by colour alone** — deductions show an explicit `−`
  and a label, the winner is named, bar charts state their amount in text, and
  leaderboard ranks are numeric.
- **The counted-up total is never announced mid-animation.** The visible figure
  animates, but its `aria-label` is pinned to the final amount from the first
  render.
- **Motion respects `prefers-reduced-motion`** — count-ups, bar growth and the
  recording pulse are all suppressed.
- Full keyboard operability with visible focus rings.
- Light and dark themes via `prefers-color-scheme`.
- Illustrations are decorative and hidden from screen readers.
