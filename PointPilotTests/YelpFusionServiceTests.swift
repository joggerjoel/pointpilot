import XCTest
@testable import PointPilot

final class YelpFusionServiceTests: XCTestCase {

    func testYelpBusinessDTOToDomainMerchantMapping() throws {
        let json = """
        {
            "id": "nobu-downtown-new-york",
            "name": "Nobu Downtown",
            "image_url": "https://s3-media0.fl.yelpcdn.com/bphoto/sample.jpg",
            "url": "https://www.yelp.com/biz/nobu-downtown-new-york",
            "rating": 4.5,
            "review_count": 1200,
            "price": "$$$$",
            "categories": [
                { "alias": "japanese", "title": "Japanese" },
                { "alias": "sushi", "title": "Sushi Bars" }
            ],
            "distance": 250.5,
            "location": {
                "address1": "195 Broadway",
                "city": "New York",
                "zip_code": "10007",
                "state": "NY"
            }
        }
        """.data(using: .utf8)!

        let yelpBusiness = try JSONDecoder().decode(YelpBusiness.self, from: json)
        let domainMerchant = yelpBusiness.toDomainMerchant()

        XCTAssertEqual(domainMerchant.name, "Nobu Downtown")
        XCTAssertEqual(domainMerchant.category, .dining)
        XCTAssertTrue(domainMerchant.aliases.contains("nobu downtown"))
        XCTAssertTrue(domainMerchant.aliases.contains("nobu downtown new york"))
    }

    func testCategoryInferenceForGroceriesAndGas() throws {
        let groceryJSON = """
        {
            "id": "whole-foods-market-ny",
            "name": "Whole Foods Market",
            "categories": [{ "alias": "grocery", "title": "Grocery" }]
        }
        """.data(using: .utf8)!

        let business = try JSONDecoder().decode(YelpBusiness.self, from: groceryJSON)
        XCTAssertEqual(business.toDomainMerchant().category, .groceries)
    }

    func testFallbackMerchantsReturnedWhenUnconfigured() async throws {
        let service = YelpFusionService(apiKey: nil)
        let result = try await service.fetchNearbyMerchants(coordinate: .defaultDemo)

        XCTAssertFalse(result.merchants.isEmpty)
        XCTAssertTrue(result.merchants.contains { $0.name == "Nobu" })
        XCTAssertTrue(result.merchants.contains { $0.name == "Shake Shack" })
        // Unconfigured must be reported as sample data, not live results.
        XCTAssertEqual(result.source, .sample)
    }

    /// A rejected key — expired trial, revoked token — must not masquerade as
    /// live nearby results. This reproduces the real `TRIAL_EXPIRED` response.
    func testRejectedKeyReportsSampleSourceRatherThanLive() async throws {
        let session = StubURLSession.make(
            statusCode: 400,
            body: #"{"error":{"code":"TRIAL_EXPIRED","description":"Your Trial has expired."}}"#
        )
        let service = YelpFusionService(apiKey: "a-real-looking-key", session: session)

        let result = try await service.fetchNearbyMerchants(coordinate: .defaultDemo)

        XCTAssertEqual(result.source, .sample)
        XCTAssertTrue(result.merchants.contains { $0.name == "Nobu" })
    }

    /// A successful response is reported as live data.
    func testSuccessfulResponseReportsLiveSource() async throws {
        let body = """
        {
            "total": 1,
            "businesses": [
                {
                    "id": "gramercy-tavern",
                    "name": "Gramercy Tavern",
                    "rating": 4.6,
                    "categories": [{ "alias": "newamerican", "title": "American" }],
                    "distance": 420.0,
                    "location": { "city": "New York" }
                }
            ]
        }
        """
        let session = StubURLSession.make(statusCode: 200, body: body)
        let service = YelpFusionService(apiKey: "a-real-looking-key", session: session)

        let result = try await service.fetchNearbyMerchants(coordinate: .defaultDemo)

        XCTAssertEqual(result.source, .live)
        XCTAssertEqual(result.merchants.first?.name, "Gramercy Tavern")
    }

    /// The request the app actually sends must be correct — asserting only the
    /// response handling would let a malformed query pass unnoticed.
    func testNearbyRequestShapeCarriesCoordinatesAndBearerToken() async throws {
        let session = StubURLSession.make(statusCode: 200, body: #"{"total":0,"businesses":[]}"#)
        let service = YelpFusionService(apiKey: "test-key-123", session: session)

        _ = try await service.fetchNearbyMerchants(coordinate: .defaultDemo)

        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "api.yelp.com")
        XCTAssertEqual(components.path, "/v3/businesses/search")

        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        // The user's coordinates must reach Yelp, or "nearby" means nothing.
        XCTAssertEqual(items["latitude"], String(LocationCoordinate.defaultDemo.latitude))
        XCTAssertEqual(items["longitude"], String(LocationCoordinate.defaultDemo.longitude))
        XCTAssertEqual(items["sort_by"], "distance")
        XCTAssertEqual(items["categories"], "restaurants,food,bars")

        // The key is sent as a bearer token, never as a query parameter — a key
        // in the URL would leak into logs and caches.
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key-123")
        XCTAssertNil(items["api_key"])
    }
}

/// Minimal URLSession stub that returns a canned HTTP response without any
/// network access, so these tests are deterministic and never call Yelp.
///
/// It also records the last request, so the wire format the app sends can be
/// asserted — not just how it handles the response.
final class StubURLSession: URLSessionProtocol, @unchecked Sendable {
    private let statusCode: Int
    private let body: String
    private(set) var lastRequest: URLRequest?

    private init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    static func make(statusCode: Int, body: String) -> StubURLSession {
        StubURLSession(statusCode: statusCode, body: body)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.yelp.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
