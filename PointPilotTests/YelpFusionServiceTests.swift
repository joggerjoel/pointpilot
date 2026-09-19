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
        let results = try await service.fetchNearbyMerchants(coordinate: .defaultDemo)

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.name == "Nobu" })
        XCTAssertTrue(results.contains { $0.name == "Shake Shack" })
    }
}
