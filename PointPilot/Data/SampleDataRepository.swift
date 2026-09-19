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

    init() {
        self.init(
            cards: Self.sampleCards,
            merchants: Self.sampleMerchants,
            offers: Self.sampleOffers,
            diningProgram: Self.sampleDiningProgram
        )
    }

    init(
        cards: [CreditCard],
        merchants: [Merchant],
        offers: [CardOffer],
        diningProgram: DiningProgram
    ) {
        self.cards = cards
        self.merchants = merchants
        self.offers = offers
        self.diningProgram = diningProgram
    }

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
            diningProgram: diningProgram
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
}
