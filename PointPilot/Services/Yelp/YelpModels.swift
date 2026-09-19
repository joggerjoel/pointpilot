import Foundation

/// Yelp Fusion API v3 Business Search Response DTOs
struct YelpSearchResponse: Codable, Sendable {
    let businesses: [YelpBusiness]
    let total: Int?
}

struct YelpBusiness: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let imageUrl: String?
    let url: String?
    let rating: Double?
    let reviewCount: Int?
    let price: String?
    let categories: [YelpCategory]?
    let distance: Double?
    let location: YelpLocation?

    enum CodingKeys: String, CodingKey {
        case id, name, url, rating, price, categories, distance, location
        case imageUrl = "image_url"
        case reviewCount = "review_count"
    }

    /// Converts Yelp business to PointPilot `Merchant` domain model.
    func toDomainMerchant() -> Merchant {
        let category = Self.mapCategory(categories)
        var aliases: [String] = []

        // Extract aliases from lowercase name variations
        aliases.append(name.lowercased())
        if let locationName = location?.city {
            aliases.append("\(name.lowercased()) \(locationName.lowercased())")
        }

        return Merchant(
            id: "yelp_\(id)",
            name: name,
            category: category,
            aliases: aliases,
            isFallback: false
        )
    }

    private static func mapCategory(_ categories: [YelpCategory]?) -> RewardCategory {
        guard let categories, !categories.isEmpty else { return .dining }
        let aliases = categories.map { $0.alias.lowercased() }

        if aliases.contains(where: { $0.contains("grocery") || $0.contains("supermarket") || $0.contains("market") }) {
            return .groceries
        }
        if aliases.contains(where: { $0.contains("gas") || $0.contains("servicestation") }) {
            return .gas
        }
        if aliases.contains(where: { $0.contains("hotel") || $0.contains("airline") || $0.contains("travel") }) {
            return .travel
        }

        return .dining
    }
}

struct YelpCategory: Codable, Sendable {
    let alias: String
    let title: String
}

struct YelpLocation: Codable, Sendable {
    let address1: String?
    let city: String?
    let zipCode: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case address1, city, state
        case zipCode = "zip_code"
    }
}
