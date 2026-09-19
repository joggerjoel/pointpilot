import Foundation

/// The single canonical source of demo data for the app.
///
/// Every card, merchant and offer lives here. Views and services read from this
/// repository and never define their own copies, so there is exactly one place
/// to change the demo. All content is fictional sample data.
struct SampleDataRepository: MerchantProviding {
    static let shared = SampleDataRepository()

    let cards: [CreditCard]
    let merchants: [Merchant]
    let offers: [CardOffer]
    let diningProgram: DiningProgram
    /// Past recommendations shown on the metrics dashboard. Demo aggregates.
    let history: [HistoryEntry]

    init() {
        self.init(
            cards: Self.sampleCards,
            merchants: Self.sampleMerchants,
            offers: Self.sampleOffers,
            diningProgram: Self.sampleDiningProgram,
            history: Self.sampleHistory
        )
    }

    init(
        cards: [CreditCard],
        merchants: [Merchant],
        offers: [CardOffer],
        diningProgram: DiningProgram,
        history: [HistoryEntry] = []
    ) {
        self.cards = cards
        self.merchants = merchants
        self.offers = offers
        self.diningProgram = diningProgram
        self.history = history
    }

    /// Aggregated figures for the metrics dashboard.
    var metrics: MetricsSummary { MetricsSummary(entries: history) }

    func card(id: String) -> CreditCard? {
        cards.first { $0.id == id }
    }

    func merchant(id: String) -> Merchant? {
        merchants.first { $0.id == id }
    }

    /// Returns a new repository enriched with dynamically discovered merchants (e.g. from Yelp).
    func withAdditionalMerchants(_ newMerchants: [Merchant]) -> SampleDataRepository {
        var existingMap = Dictionary(uniqueKeysWithValues: merchants.map { ($0.id, $0) })
        for m in newMerchants {
            if existingMap[m.id] == nil {
                existingMap[m.id] = m
            }
        }
        return SampleDataRepository(
            cards: cards,
            merchants: Array(existingMap.values),
            offers: offers,
            diningProgram: diningProgram,
            history: history
        )
    }



    // MARK: - Cards

    static let amexGoldID = "amex-gold"
    static let sapphirePreferredID = "chase-sapphire-preferred"
    static let ventureID = "capital-one-venture"

    static let sampleCards: [CreditCard] = [
        CreditCard(
            id: amexGoldID,
            name: "Amex Gold",
            issuer: "Sample Bank",
            rewardUnitName: "points",
            multipliers: [.dining: 4, .groceries: 4, .travel: 3],
            defaultMultiplier: 1,
            pointValue: Decimal(string: "0.02") ?? 0,
            annualFee: 250,
            priority: 0,
            accentHex: "#B99A5B"
        ),
        CreditCard(
            id: sapphirePreferredID,
            name: "Chase Sapphire Preferred",
            issuer: "Sample Bank",
            rewardUnitName: "points",
            multipliers: [.dining: 3, .travel: 2, .groceries: 1],
            defaultMultiplier: 1,
            pointValue: Decimal(string: "0.0175") ?? 0,
            annualFee: 95,
            priority: 1,
            accentHex: "#2F6BA8"
        ),
        CreditCard(
            id: ventureID,
            name: "Capital One Venture",
            issuer: "Sample Bank",
            rewardUnitName: "miles",
            multipliers: [:],
            defaultMultiplier: 2,
            pointValue: Decimal(string: "0.01") ?? 0,
            annualFee: 95,
            priority: 2,
            accentHex: "#8C2F39"
        )
    ]

    // MARK: - Merchants

    static let nobuID = "nobu"
    static let shakeShackID = "shake-shack"
    static let chipotleID = "chipotle"
    static let starbucksID = "starbucks"
    static let wholeFoodsID = "whole-foods"
    static let shellID = "shell"
    static let appleStoreID = "apple-store"
    static let amcID = "amc-theatres"
    static let genericRestaurantID = "generic-restaurant"

    static let sampleMerchants: [Merchant] = [
        Merchant(
            id: nobuID,
            name: "Nobu",
            category: .dining,
            aliases: ["nobu downtown", "nobu malibu", "nobu sushi"]
        ),
        Merchant(
            id: shakeShackID,
            name: "Shake Shack",
            category: .dining,
            aliases: ["shakeshack", "shake shack burger"]
        ),
        Merchant(
            id: chipotleID,
            name: "Chipotle",
            category: .dining,
            aliases: ["chipotle mexican grill"]
        ),
        Merchant(
            id: starbucksID,
            name: "Starbucks",
            category: .dining,
            aliases: ["starbucks coffee"]
        ),
        // Non-dining sample merchants. These exist so the dashboard can show a
        // realistic spread of categories without pretending a restaurant is a
        // grocery store.
        Merchant(
            id: wholeFoodsID,
            name: "Whole Foods",
            category: .groceries,
            aliases: ["whole foods market"]
        ),
        Merchant(
            id: shellID,
            name: "Shell",
            category: .gas,
            aliases: ["shell gas", "shell station"]
        ),
        Merchant(
            id: appleStoreID,
            name: "Apple Store",
            category: .clothing,
            aliases: ["apple", "apple store retail"]
        ),
        Merchant(
            id: amcID,
            name: "AMC Theatres",
            category: .entertainment,
            aliases: ["amc", "amc theaters"]
        ),
        Merchant(
            id: genericRestaurantID,
            name: "Restaurant",
            category: .dining,
            aliases: ["restaurant", "dinner", "lunch", "generic restaurant"],
            isFallback: true
        )
    ]

    // MARK: - Offers

    static let sampleOffers: [CardOffer] = [
        // Nobu: 10% back with Amex Gold, capped at $20.
        CardOffer(
            id: "offer-nobu-amex",
            cardID: amexGoldID,
            merchantID: nobuID,
            kind: .percentage(Decimal(string: "0.10") ?? 0),
            maximumValue: 20,
            requiresActivation: true
        ),
        // Shake Shack: $5 back with Chase Sapphire Preferred.
        CardOffer(
            id: "offer-shakeshack-sapphire",
            cardID: sapphirePreferredID,
            merchantID: shakeShackID,
            kind: .flatCash(5),
            maximumValue: 5,
            requiresActivation: true
        ),
        // Chipotle: 5% back with Capital One Venture, capped at $10.
        CardOffer(
            id: "offer-chipotle-venture",
            cardID: ventureID,
            merchantID: chipotleID,
            kind: .percentage(Decimal(string: "0.05") ?? 0),
            maximumValue: 10,
            requiresActivation: false
        )
    ]

    // MARK: - Airline dining program

    /// Participating restaurants earn 3 airline miles per dollar, valued at
    /// $0.015 per mile. The program applies to every card, since it is a
    /// property of the restaurant rather than the card.
    static let sampleDiningProgram = DiningProgram(
        id: "airline-dining",
        name: "Airline Dining Rewards",
        milesPerDollar: 3,
        mileValue: Decimal(string: "0.015") ?? 0,
        eligibleMerchantIDs: [nobuID, shakeShackID, chipotleID]
    )

    // MARK: - History (demo aggregates)

    /// A past purchase to replay through the engine.
    private struct HistorySpec {
        let id: String
        let merchantQuery: String
        let amount: Decimal
        /// The card the user reached for. May be worse than the winner, which
        /// is what makes the "money left on the table" figure non-zero.
        let usedCardID: String
        let daysAgo: Int
    }

    /// The purchases the dashboard replays.
    ///
    /// Several deliberately use a card that is *not* the winner, so the missed
    /// value figure reflects a real alternative rather than a hypothetical one.
    private static let sampleHistorySpecs: [HistorySpec] = [
        HistorySpec(id: "h-01", merchantQuery: "Nobu", amount: 200, usedCardID: amexGoldID, daysAgo: 2),
        HistorySpec(id: "h-02", merchantQuery: "Whole Foods", amount: 140, usedCardID: sapphirePreferredID, daysAgo: 4),
        HistorySpec(id: "h-03", merchantQuery: "Shake Shack", amount: 28, usedCardID: sapphirePreferredID, daysAgo: 6),
        HistorySpec(id: "h-04", merchantQuery: "Shell", amount: 62, usedCardID: ventureID, daysAgo: 9),
        HistorySpec(id: "h-05", merchantQuery: "Chipotle", amount: 19, usedCardID: ventureID, daysAgo: 12),
        HistorySpec(id: "h-06", merchantQuery: "Apple Store", amount: 320, usedCardID: amexGoldID, daysAgo: 15),
        HistorySpec(id: "h-07", merchantQuery: "AMC Theatres", amount: 46, usedCardID: sapphirePreferredID, daysAgo: 21),
        HistorySpec(id: "h-08", merchantQuery: "Starbucks", amount: 12, usedCardID: amexGoldID, daysAgo: 26)
    ]

    /// A merchant provider built from the static sample data.
    ///
    /// Exists so the history can be computed without constructing a
    /// `SampleDataRepository`, which would recurse through this very property.
    private struct StaticMerchantProvider: MerchantProviding {
        let merchants: [Merchant]
        let offers: [CardOffer]
        let diningProgram: DiningProgram
    }

    /// Demo history, computed by the real engine.
    ///
    /// Deriving these figures rather than hard-coding them is what keeps the
    /// dashboard honest: the earned and best-possible values are exactly what
    /// `RecommendationEngine` produces, so the totals on the metrics screen can
    /// never drift from the numbers the app shows when you ask for a card.
    static let sampleHistory: [HistoryEntry] = {
        let provider = StaticMerchantProvider(
            merchants: sampleMerchants,
            offers: sampleOffers,
            diningProgram: sampleDiningProgram
        )
        let engine = RecommendationEngine(cards: sampleCards, merchantProvider: provider)

        return sampleHistorySpecs.compactMap { spec in
            guard let result = try? engine.recommend(
                merchantQuery: spec.merchantQuery,
                amount: spec.amount
            ) else { return nil }
            guard let used = result.ranked.first(where: { $0.card.id == spec.usedCardID }) else {
                return nil
            }

            return HistoryEntry(
                id: spec.id,
                merchantName: result.merchantName,
                category: result.category,
                amount: spec.amount,
                usedCardID: used.card.id,
                usedCardName: used.card.name,
                earned: used.totalValue,
                bestPossible: result.winner.totalValue,
                daysAgo: spec.daysAgo
            )
        }
    }()
}
