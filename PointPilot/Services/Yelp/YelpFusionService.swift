import Foundation

/// Live Yelp Fusion API client.
///
/// Complies with Council mandates:
/// - 5-second aggressive timeout so UI never lags.
/// - Graceful fallback to local sample merchants if unconfigured or offline.
/// - Never logs API keys or raw bearer headers.
final class YelpFusionService: MerchantDataProviding, @unchecked Sendable {
    private let apiKey: String?
    private let session: URLSession
    private let fallbackMerchants: [Merchant]

    init(
        apiKey: String? = AppEnvironment.shared.yelpAPIKey,
        session: URLSession = .shared,
        fallbackMerchants: [Merchant] = SampleDataRepository.sampleMerchants
    ) {
        self.apiKey = apiKey
        self.session = session
        self.fallbackMerchants = fallbackMerchants.filter { !$0.isFallback }
    }

    var isConfigured: Bool {
        guard let apiKey else { return false }
        return !apiKey.isEmpty && apiKey != "YOUR_YELP_API_KEY_HERE"
    }

    func fetchNearbyMerchants(coordinate: LocationCoordinate) async throws -> [Merchant] {
        guard isConfigured, let apiKey else {
            // Unconfigured or demo mode: return local sample merchants
            return fallbackMerchants
        }

        var components = URLComponents(string: "https://api.yelp.com/v3/businesses/search")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "categories", value: "restaurants,food,bars"),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "sort_by", value: "distance")
        ]

        guard let url = components?.url else {
            return fallbackMerchants
        }

        var request = URLRequest(url: url, timeoutInterval: 5.0)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return fallbackMerchants
            }

            let decoded = try JSONDecoder().decode(YelpSearchResponse.self, from: data)
            let merchants = decoded.businesses.map { $0.toDomainMerchant() }
            return merchants.isEmpty ? fallbackMerchants : merchants
        } catch {
            // On network failure / timeout, return fallback merchants seamlessly
            return fallbackMerchants
        }
    }

    func searchMerchants(query: String, coordinate: LocationCoordinate?) async throws -> [Merchant] {
        guard isConfigured, let apiKey, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallbackMerchants.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        var components = URLComponents(string: "https://api.yelp.com/v3/businesses/search")
        var queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "categories", value: "restaurants,food,bars"),
            URLQueryItem(name: "limit", value: "5")
        ]

        if let coordinate {
            queryItems.append(URLQueryItem(name: "latitude", value: String(coordinate.latitude)))
            queryItems.append(URLQueryItem(name: "longitude", value: String(coordinate.longitude)))
        } else {
            queryItems.append(URLQueryItem(name: "location", value: "New York, NY"))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            return fallbackMerchants
        }

        var request = URLRequest(url: url, timeoutInterval: 5.0)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return fallbackMerchants
            }

            let decoded = try JSONDecoder().decode(YelpSearchResponse.self, from: data)
            return decoded.businesses.map { $0.toDomainMerchant() }
        } catch {
            return fallbackMerchants
        }
    }
}
