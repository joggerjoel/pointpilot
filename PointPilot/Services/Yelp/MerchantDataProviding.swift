import Foundation

/// Boundary protocol for fetching real-time merchant suggestions (e.g. Yelp, Google Places, or Local Mock).
protocol MerchantDataProviding: Sendable {
    /// Fetches nearby merchants based on coordinates.
    func fetchNearbyMerchants(coordinate: LocationCoordinate) async throws -> [Merchant]

    /// Searches merchants by free-text keyword.
    func searchMerchants(query: String, coordinate: LocationCoordinate?) async throws -> [Merchant]
}
