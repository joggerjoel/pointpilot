import Foundation

/// A merchant the user might be spending at.
struct Merchant: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: RewardCategory
    /// Alternate spellings and shorthand the voice agent or typed input may produce.
    let aliases: [String]
    /// True for the catch-all entry used when nothing else matches.
    let isFallback: Bool

    init(
        id: String,
        name: String,
        category: RewardCategory,
        aliases: [String] = [],
        isFallback: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.aliases = aliases
        self.isFallback = isFallback
    }
}

/// Supplies merchants and offers to the recommendation engine.
///
/// Kept as a protocol so the engine can be tested against a fixed fixture set
/// without touching the shipped sample data.
protocol MerchantProviding: Sendable {
    var merchants: [Merchant] { get }
    var offers: [CardOffer] { get }
    var diningProgram: DiningProgram { get }

    /// Resolves free-text input to a known merchant, or `nil` when unknown.
    func merchant(matching query: String) -> Merchant?
}

extension MerchantProviding {
    /// Normalizes a query so matching is case-, punctuation- and
    /// whitespace-insensitive: "  The NOBU! " becomes "nobu".
    static func normalize(_ query: String) -> String {
        let lowered = query.lowercased()
        let kept = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " "
        }
        return String(String.UnicodeScalarView(kept))
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Default matching strategy: exact name, then alias, then containment.
    ///
    /// Containment is checked last and on the shortest candidate first so that
    /// "nobu downtown" resolves to "Nobu" rather than a longer, weaker match.
    func merchant(matching query: String) -> Merchant? {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return nil }

        let candidates = merchants.filter { !$0.isFallback }

        for merchant in candidates where Self.normalize(merchant.name) == needle {
            return merchant
        }
        for merchant in candidates {
            let names = [merchant.name] + merchant.aliases
            if names.contains(where: { Self.normalize($0) == needle }) {
                return merchant
            }
        }

        let contained = candidates
            .filter { merchant in
                let names = [merchant.name] + merchant.aliases
                return names.contains { name in
                    let normalized = Self.normalize(name)
                    return !normalized.isEmpty && needle.contains(normalized)
                }
            }
            .sorted { lhs, rhs in
                if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
                return lhs.priorityFallbackKey < rhs.priorityFallbackKey
            }

        return contained.first
    }

    /// The catch-all merchant used when nothing matches.
    var fallbackMerchant: Merchant? {
        merchants.first { $0.isFallback }
    }
}

private extension Merchant {
    /// Stable ordering key so equal-length containment matches resolve deterministically.
    var priorityFallbackKey: String { id }
}
