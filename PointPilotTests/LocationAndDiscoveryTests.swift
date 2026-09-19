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
        private(set) var fetchCallCount = 0
        private(set) var lastQueryCoordinate: LocationCoordinate?

        func fetchNearbyMerchants(coordinate: LocationCoordinate) async throws -> [Merchant] {
            fetchCallCount += 1
            lastQueryCoordinate = coordinate
            return stubbedMerchants
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
}
