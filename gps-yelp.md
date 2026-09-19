# PointPilot GPS + Yelp Integration Plan & Council Review

## 1. Council of Experts

### Member 1: Senior iOS Architect
- **Focus**: Concurrency, service boundaries, lifecycle management, failure resiliency.
- **Verdict & Mandates**:
  - `LocationService` must use Swift Concurrency (`AsyncStream` or `@Observable`) and `CLLocationManager`.
  - CoreLocation authorization must be requested strictly on-demand (`requestWhenInUseAuthorization`), never implicitly blocking the launch.
  - `YelpFusionService` must conform to a protocol `MerchantDataProviding` and use standard `URLSession` (no heavyweight third-party networking pods).
  - All network calls must handle timeouts (5s max for snappy UI) and seamlessly fall back to local sample merchants if offline or if the Yelp API quota/token fails.
  - No main-thread blocking during reverse geocoding or Yelp API parsing.

### Member 2: Product & Design Lead
- **Focus**: 1-handed mobile ergonomics, cognitive load, zero-friction demo.
- **Verdict & Mandates**:
  - Keep the large voice button as the primary visual anchor.
  - Add a subtle location pill or quick-pick horizontal row: e.g. "📍 Nearby: [Nobu] [Shake Shack] [Chipotle] [Starbucks]".
  - Tapping a nearby merchant pill auto-fills the merchant field with 1 tap.
  - An inline "Detect Location" button beside the merchant field so the user can re-trigger GPS anytime.
  - Show clear status if location is disabled or searching, but never block the user from typing or using voice.

### Member 3: Security & Privacy Specialist
- **Focus**: Token safety, git leakage, privacy descriptions.
- **Verdict & Mandates**:
  - `.env` and `PointPilot/Config/PointPilot.env` MUST be in `.gitignore`.
  - Provide a safe `.env.example` template with dummy values.
  - Implement a runtime `.env` parser that loads key-value pairs into `ProcessInfo` or an in-memory configuration struct without hardcoding secrets in compiled Swift binaries.
  - Ensure `NSLocationWhenInUseUsageDescription` is clearly set in `Info.plist` with plain English justification ("PointPilot uses your location to discover nearby restaurants and find your best credit card rewards.").
  - Do not log or leak user GPS coordinates or auth headers to stdout/console in release builds.

### Member 4: Financial & Recommendation Engine Specialist
- **Focus**: Calculation integrity, unknown merchant handling, category mapping.
- **Verdict & Mandates**:
  - Real Yelp restaurants must map cleanly to `RewardCategory.dining` (or other categories if present).
  - When Yelp returns a restaurant that has no specific Amex/Chase merchant offer in the local database, the engine MUST deterministically use standard category multipliers and NOT invent fake merchant offers.
  - If Yelp returns a known merchant (e.g., Nobu, Shake Shack, Chipotle), the offer mapping must link seamlessly by alias/normalized name matching.
  - Currency arithmetic remains 100% in `Decimal`.

---

## 2. Architecture & File Structure

```
PointPilot/
├── Config/
│   ├── .env.example                     (Committed: placeholder template)
│   ├── PointPilot.env                   (Gitignored: real token storage)
│   └── AppEnvironment.swift             (Loads .env / ProcessInfo / Bundle)
├── Services/
│   ├── Location/
│   │   ├── LocationServiceProtocol.swift
│   │   └── LocationService.swift        (CoreLocation wrapper)
│   └── Yelp/
│       ├── YelpModels.swift             (Yelp Fusion API DTOs)
│       ├── MerchantDataProviding.swift  (Boundary protocol)
│       └── YelpFusionService.swift      (Fusion v3 API client)
├── Models/
│   └── (Existing: Rewards, CreditCard, Merchant)
├── Engine/
│   └── (Existing: RecommendationEngine with dynamic merchant support)
├── Views/
│   ├── AskView.swift                    (Updated: location pill & nearby suggestions)
│   └── AskViewModel.swift               (Updated: orchestrates GPS, Yelp, Voice & Engine)
```

---

## 3. Step-by-Step Implementation Roadmap

1. **Environment & Secret Management**:
   - Create `.env.example` and load routine in `AppEnvironment.swift`.
   - Update `.gitignore` to ensure `.env` and `*.env` are excluded.
2. **Location Service**:
   - `LocationService` wrapping `CLLocationManager` with async coordinate fetching.
   - Update `project.yml` with `NSLocationWhenInUseUsageDescription`.
3. **Yelp Fusion Service**:
   - Implement `https://api.yelp.com/v3/businesses/search` endpoint.
   - Search parameters: `latitude`, `longitude`, `categories=restaurants,food,bars`, `limit=6`, `sort_by=distance`.
   - Map Yelp businesses to PointPilot `Merchant` models.
4. **View Model & UI Enhancement**:
   - `AskViewModel` calls location & Yelp on appear or on "Detect" button tap.
   - Display a clean horizontal scroll of nearby restaurants as quick-tap chips.
   - Tapping a chip immediately populates `merchantQuery` and highlights if special card offers exist.
5. **Testing**:
   - Unit tests for `AppEnvironment` (.env parsing).
   - Unit tests for `YelpFusionService` mapping & offline fallback.
   - Unit tests for `LocationService` mocking.
   - UI tests verifying nearby merchant chips tap-to-populate flow.
6. **Project Generation & Build Verification**:
   - Run `xcodegen generate` and `xcodebuild` clean test on iPhone 17 simulator.
