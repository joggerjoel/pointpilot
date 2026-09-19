import XCTest
@testable import PointPilot

@MainActor
final class LocationAndDiscoveryTests: XCTestCase {

    /// Records whether the OS-level permission prompt was ever triggered.
    final class MockLocationService: LocationServiceProtocol {
        var state: LocationState = .notDetermined
        var onStateChange: ((LocationState) -> Void)?
        var stubbedCoordinate: LocationCoordinate? = LocationCoordinate(latitude: 40.7128, longitude: -74.0060)

        /// Set to true when `requestLocation()` runs — this is what shows the
        /// system permission dialog, so tests assert it stays false until the
        /// user explicitly asks for nearby restaurants.
        private(set) var didRequestLocation = false

        func requestLocation() async -> LocationCoordinate? {
            didRequestLocation = true
            guard let coordinate = stubbedCoordinate else {
                state = .denied
                onStateChange?(state)
                return nil
            }
            state = .authorized(coordinate)
            onStateChange?(state)
            return coordinate
        }
    }

    final class MockMerchantDataService: MerchantDataProviding {
        var stubbedMerchants: [Merchant] = [
            Merchant(id: "yelp_gramercy", name: "Gramercy Tavern", category: .dining)
        ]
        /// What the mock reports about the data's provenance.
        var stubbedSource: MerchantSource = .live
        private(set) var fetchCallCount = 0
        private(set) var lastQueryCoordinate: LocationCoordinate?

        func fetchNearbyMerchants(coordinate: LocationCoordinate) async throws -> NearbyMerchants {
            fetchCallCount += 1
            lastQueryCoordinate = coordinate
            return NearbyMerchants(merchants: stubbedMerchants, source: stubbedSource)
        }

        func searchMerchants(query: String, coordinate: LocationCoordinate?) async throws -> [Merchant] {
            return stubbedMerchants.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private func makeViewModel(
        location: MockLocationService,
        merchants: MockMerchantDataService
    ) -> AskViewModel {
        let repo = SampleDataRepository.shared
        return AskViewModel(
            engine: RecommendationEngine(cards: repo.cards, merchantProvider: repo),
            repository: repo,
            voiceService: MockVoiceAgentService(),
            locationService: location,
            merchantDataService: merchants,
            voiceIsConfigured: false
        )
    }

    /// Launching must never trigger the system location permission dialog.
    ///
    /// Regression test: the Ask screen previously fired a location request on
    /// appear, so the permission alert greeted the user before they had asked
    /// for anything.
    func testLoadingDefaultMerchantsDoesNotRequestLocationPermission() async {
        let location = MockLocationService()
        let merchants = MockMerchantDataService()
        let viewModel = makeViewModel(location: location, merchants: merchants)

        viewModel.loadDefaultNearbyMerchants()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(
            location.didRequestLocation,
            "Launch must not request location — the permission dialog would appear before any user action"
        )
        XCTAssertEqual(
            merchants.fetchCallCount, 0,
            "Launch must not query the merchant service"
        )
        // Chips are still populated, from local sample data.
        XCTAssertFalse(viewModel.nearbyMerchants.isEmpty)
        XCTAssertTrue(viewModel.nearbyMerchants.contains { $0.name == "Nobu" })
    }

    /// An explicit "Nearby" tap does request location and fetches real venues.
    func testUserInitiatedDetectionFetchesNearbyMerchantsAndAllowsOneTapSelection() async {
        let location = MockLocationService()
        let merchants = MockMerchantDataService()
        let viewModel = makeViewModel(location: location, merchants: merchants)

        viewModel.detectLocationAndFetchNearby()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(location.didRequestLocation)
        XCTAssertEqual(merchants.fetchCallCount, 1)
        XCTAssertEqual(viewModel.nearbyMerchants.count, 1)
        XCTAssertEqual(viewModel.nearbyMerchants.first?.name, "Gramercy Tavern")
        XCTAssertFalse(viewModel.isLocating, "The locating state must clear when the work finishes")

        // One-tap selection populates the merchant field.
        guard let merchant = viewModel.nearbyMerchants.first else {
            return XCTFail("Expected a nearby merchant to select")
        }
        viewModel.selectNearbyMerchant(merchant)
        XCTAssertEqual(viewModel.merchantQuery, "Gramercy Tavern")
    }

    /// When location is unavailable, keep local merchants and never query the
    /// merchant service with invented coordinates.
    ///
    /// Regression test: the app previously substituted hardcoded demo
    /// coordinates on failure, which would present unrelated restaurants as
    /// though they were around the user.
    func testLocationFailureKeepsLocalMerchantsAndInventNothing() async {
        let location = MockLocationService()
        location.stubbedCoordinate = nil
        let merchants = MockMerchantDataService()
        let viewModel = makeViewModel(location: location, merchants: merchants)

        viewModel.detectLocationAndFetchNearby()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(location.didRequestLocation)
        XCTAssertEqual(
            merchants.fetchCallCount, 0,
            "No merchant query may be made without a real location fix"
        )
        XCTAssertNil(merchants.lastQueryCoordinate)
        // Falls back to the local sample venues rather than an empty or invented list.
        XCTAssertTrue(viewModel.nearbyMerchants.contains { $0.name == "Nobu" })
        XCTAssertFalse(viewModel.isLocating)
    }

    // MARK: - Location state is explained, not swallowed

    /// A denied permission must produce an explanation the UI can show.
    ///
    /// `gps-yelp.md` mandated "show clear status if location is disabled or
    /// searching". Only the searching half shipped at first: `locationState` was
    /// recorded and then never read, so a denied user saw a button that appeared
    /// to do nothing.
    func testDeniedLocationProducesAnExplanation() async {
        let location = MockLocationService()
        location.stubbedCoordinate = nil
        let viewModel = makeViewModel(location: location, merchants: MockMerchantDataService())

        XCTAssertNil(
            viewModel.locationNotice,
            "Nothing should be shown before the user asks for location"
        )

        viewModel.detectLocationAndFetchNearby()
        try? await Task.sleep(nanoseconds: 100_000_000)

        let notice = viewModel.locationNotice
        XCTAssertNotNil(notice, "A denied permission must be explained to the user")
        XCTAssertTrue(
            notice?.contains("Location is off") == true,
            "The notice should name the cause, got: \(notice ?? "nil")"
        )
        // It must also point at the path that still works.
        XCTAssertTrue(
            notice?.contains("type a merchant") == true,
            "The notice should offer the typed alternative"
        )
    }

    /// Restricted and error states are surfaced too, each naming its cause.
    func testRestrictedAndErrorStatesAreExplained() {
        let location = MockLocationService()
        let viewModel = makeViewModel(location: location, merchants: MockMerchantDataService())

        // The view model observes the service's state changes, so driving the
        // callback is enough to exercise the mapping.
        location.onStateChange?(.restricted)
        var notice = viewModel.locationNotice
        XCTAssertTrue(
            notice?.contains("restricted") == true,
            "A restricted device must be explained, got: \(notice ?? "nil")"
        )

        location.onStateChange?(.error("network unavailable"))
        notice = viewModel.locationNotice
        XCTAssertTrue(
            notice?.contains("network unavailable") == true,
            "The underlying error must be named, got: \(notice ?? "nil")"
        )

        // Healthy states stay quiet.
        location.onStateChange?(.requesting)
        XCTAssertNil(viewModel.locationNotice, "A search in progress is not a problem")
        location.onStateChange?(.notDetermined)
        XCTAssertNil(viewModel.locationNotice)
    }

    /// Success is not treated as a problem.
    func testSuccessfulLocationShowsNoNotice() async {
        let location = MockLocationService()
        let viewModel = makeViewModel(location: location, merchants: MockMerchantDataService())

        viewModel.detectLocationAndFetchNearby()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(
            viewModel.locationNotice,
            "A successful fix must not show a warning"
        )
    }

    // MARK: - Typed input to the voice agent

    /// Typing to the agent exercises the same parse-and-compute path as speech.
    ///
    /// `sendVoiceText` existed with no call site, so the conversational flow was
    /// untestable and unreachable without a microphone. This pins the behaviour
    /// the new input field relies on.
    func testTypedVoiceInputProducesARecommendation() async {
        let viewModel = makeViewModel(
            location: MockLocationService(),
            merchants: MockMerchantDataService()
        )

        // The agent only accepts input during a live session, so the session has
        // to be running — exactly what tapping the mic does in the UI.
        viewModel.toggleVoice()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isVoiceBusy, "The session should be running")

        viewModel.sendVoiceText("I'm at Nobu and spending around $200")
        try? await Task.sleep(nanoseconds: 200_000_000)

        let recommendation = try? XCTUnwrap(viewModel.recommendation)
        XCTAssertEqual(recommendation?.winner.card.name, "Amex Gold")
        // The same figure the typed form produces — voice adds no separate math.
        XCTAssertEqual(recommendation?.winner.totalValue, Decimal(45))
        // And the exchange shows up in the transcript.
        XCTAssertTrue(viewModel.messages.contains { $0.speaker == .user })
    }

    /// Empty or whitespace-only input is ignored rather than sent.
    func testBlankTypedVoiceInputIsIgnored() async {
        let viewModel = makeViewModel(
            location: MockLocationService(),
            merchants: MockMerchantDataService()
        )

        viewModel.toggleVoice()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let greetingCount = viewModel.messages.count

        viewModel.sendVoiceText("   ")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(viewModel.recommendation)
        // The blank line must not reach the transcript, so only the greeting remains.
        XCTAssertEqual(
            viewModel.messages.count, greetingCount,
            "A blank line should not be sent to the agent"
        )
    }

    /// Text sent while no session is running is ignored, not queued.
    func testTypedVoiceInputIsIgnoredWhenNoSessionIsRunning() async {
        let viewModel = makeViewModel(
            location: MockLocationService(),
            merchants: MockMerchantDataService()
        )

        viewModel.sendVoiceText("I'm at Nobu and spending around $200")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertNil(
            viewModel.recommendation,
            "The agent must not act on input with no live session"
        )
    }

    // MARK: - Nearby source disclosure

    /// Before the user asks for nearby venues, the chips are the bundled
    /// defaults and nothing should be disclosed — a notice on launch would be
    /// noise, and claiming live data is unavailable before trying is untrue.
    func testNoSampleNoticeBeforeAnyNearbyAttempt() async {
        let viewModel = makeViewModel(
            location: MockLocationService(),
            merchants: MockMerchantDataService()
        )

        viewModel.loadDefaultNearbyMerchants()

        XCTAssertFalse(
            viewModel.showsSampleSourceNotice,
            "Launch must not claim live results are unavailable before asking"
        )
    }

    /// A fetch that returns sample data — an expired key, a revoked key, an
    /// outage — must disclose that, so bundled venues are not read as live
    /// results near the user.
    func testSampleSourceIsDisclosedAfterAFailedLiveLookup() async {
        let location = MockLocationService()
        let merchants = MockMerchantDataService()
        merchants.stubbedSource = .sample
        let viewModel = makeViewModel(location: location, merchants: merchants)

        viewModel.detectLocationAndFetchNearby()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(viewModel.didAttemptNearbyFetch)
        XCTAssertEqual(viewModel.nearbySource, .sample)
        XCTAssertTrue(
            viewModel.showsSampleSourceNotice,
            "Sample venues must be disclosed after a real lookup, not passed off as live"
        )
    }

    /// Live results carry no caveat.
    func testLiveSourceIsNotDisclosed() async {
        let location = MockLocationService()
        let merchants = MockMerchantDataService()
        merchants.stubbedSource = .live
        let viewModel = makeViewModel(location: location, merchants: merchants)

        viewModel.detectLocationAndFetchNearby()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.nearbySource, .live)
        XCTAssertFalse(
            viewModel.showsSampleSourceNotice,
            "Live results must not carry a sample-data caveat"
        )
    }
}
