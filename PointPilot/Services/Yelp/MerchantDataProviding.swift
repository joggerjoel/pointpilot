import Foundation

/// Where a set of nearby merchants came from.
///
/// The distinction is load-bearing for honesty: a rejected API key, an expired
/// trial, a timeout and "no restaurants within range" all used to collapse into
/// the same silent fallback, so the UI showed bundled sample venues as though
/// they had been found nearby. Carrying the source through lets the UI say so.
enum MerchantSource: Sendable, Equatable {
    /// Fetched live from the merchant API for the user's coordinates.
    case live
    /// Bundled sample venues, used when the API is unconfigured or unreachable.
    case sample
}

/// Nearby merchants plus their provenance.
struct NearbyMerchants: Sendable, Equatable {
    let merchants: [Merchant]
    let source: MerchantSource
}

/// Boundary protocol for fetching real-time merchant suggestions (e.g. Yelp, Google Places, or Local Mock).
protocol MerchantDataProviding: Sendable {
    /// Fetches nearby merchants based on coordinates, reporting their source.
    func fetchNearbyMerchants(coordinate: LocationCoordinate) async throws -> NearbyMerchants

    /// Searches merchants by free-text keyword.
    func searchMerchants(query: String, coordinate: LocationCoordinate?) async throws -> [Merchant]
}
