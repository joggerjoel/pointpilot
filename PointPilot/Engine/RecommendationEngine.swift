import Foundation

/// The evaluation of a single card for a single purchase.
struct CardEvaluation: Identifiable, Hashable, Sendable {
    let card: CreditCard
    /// Ordered, individually explainable line items. These sum exactly to `totalValue`.
    let components: [RewardComponent]
    /// Total estimated dollar value, equal to the sum of `components`.
    let totalValue: Decimal
    /// Set when this card has an offer at this merchant that must be activated.
    let offerRequiringActivation: CardOffer?

    var id: String { card.id }

    /// The card's reward component, for the headline rate line.
    var baseReward: RewardComponent? {
        components.first { $0.kind == .baseReward }
    }
}

/// The full recommendation produced by the engine.
struct CardRecommendation: Hashable, Sendable, Identifiable {
    let winner: CardEvaluation
    let runnerUp: CardEvaluation?
    /// Every card the user holds, ranked best first. The winner is `ranked.first`.
    let ranked: [CardEvaluation]
    let merchantName: String
    let amount: Decimal
    let category: RewardCategory
    /// True when the merchant was not recognized and the dining-category
    /// calculation was used with no merchant offer.
    let usedFallbackMerchant: Bool
    /// One-sentence, fact-only explanation suitable for display and speech.
    let explanation: String
    let warnings: [String]

    var advantageOverRunnerUp: Decimal {
        guard let runnerUp else { return 0 }
        return winner.totalValue - runnerUp.totalValue
    }

    /// Identity for presentation, so the result can drive a sheet.
    var id: String {
        "\(winner.card.id)|\(merchantName)|\(amount)|\(winner.totalValue)"
    }
}

/// A validation failure that prevents a recommendation from being produced.
enum RecommendationError: LocalizedError, Equatable {
    case invalidAmount(Decimal)
    case noCardsAvailable

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Enter a purchase amount greater than $0.00."
        case .noCardsAvailable:
            return "Add a card to your wallet to get a recommendation."
        }
    }
}

/// Produces a card recommendation. Implemented by `RecommendationEngine`.
///
/// The protocol is the boundary the UI and the voice agent depend on, so the
/// engine can be swapped or faked in tests without touching either.
protocol RecommendationProviding: Sendable {
    func recommend(merchantQuery: String, amount: Decimal) throws -> CardRecommendation
}

/// The deterministic recommendation engine.
///
/// This type is pure: it holds no mutable state, performs no I/O, and depends on
/// nothing outside the model layer. Given the same inputs it always returns the
/// same output, which is what makes it independently testable.
struct RecommendationEngine: RecommendationProviding {
    let cards: [CreditCard]
    let merchantProvider: MerchantProviding
    /// When true, a card's annual fee is charged against this single purchase.
    ///
    /// Off by default: amortizing a full annual fee onto one transaction would
    /// make every card look unprofitable and does not reflect how the decision
    /// is actually made at the register. The formula supports it for
    /// completeness, and the trade-off is documented in the README.
    let includeAnnualFeeInValue: Bool

    init(
        cards: [CreditCard],
        merchantProvider: MerchantProviding,
        includeAnnualFeeInValue: Bool = false
    ) {
        self.cards = cards
        self.merchantProvider = merchantProvider
        self.includeAnnualFeeInValue = includeAnnualFeeInValue
    }

    func recommend(merchantQuery: String, amount: Decimal) throws -> CardRecommendation {
        guard !cards.isEmpty else { throw RecommendationError.noCardsAvailable }
        guard amount > 0 else { throw RecommendationError.invalidAmount(amount) }

        let spend = Currency.rounded(amount)
        let matched = merchantProvider.merchant(matching: merchantQuery)

        // An unknown merchant falls back to the dining-category calculation and
        // never invents a merchant offer.
        let merchant = matched ?? merchantProvider.fallbackMerchant
        let resolvedName = merchant?.name ?? Self.unknownMerchantName
        let resolvedID = merchant?.id ?? Self.unknownMerchantID
        let category = merchant?.category ?? .dining
        let isFallback = matched == nil

        let evaluations = cards
            .map { evaluate(card: $0, amount: spend, merchantID: resolvedID, category: category) }
            .sorted(by: Self.rank)

        guard let winner = evaluations.first else { throw RecommendationError.noCardsAvailable }
        let runnerUp = evaluations.dropFirst().first

        var warnings: [String] = []
        if isFallback, !merchantQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(
                "We don't have an offer for “\(merchantQuery)”. Showing standard dining rewards."
            )
        }
        if let offer = winner.offerRequiringActivation {
            warnings.append("Activate the \(offer.shortDescription) offer before you pay to earn it.")
        }

        return CardRecommendation(
            winner: winner,
            runnerUp: runnerUp,
            ranked: evaluations,
            merchantName: resolvedName,
            amount: spend,
            category: category,
            usedFallbackMerchant: isFallback,
            explanation: Self.explain(winner: winner, runnerUp: runnerUp, merchantName: resolvedName),
            warnings: warnings
        )
    }

    // MARK: - Evaluation

    /// Builds the value breakdown for one card.
    ///
    /// Components are computed, rounded to cents individually, then summed, so
    /// the lines a user reads always add up to the total they read.
    private func evaluate(
        card: CreditCard,
        amount: Decimal,
        merchantID: String,
        category: RewardCategory
    ) -> CardEvaluation {
        var components: [RewardComponent] = []

        let multiplier = card.multiplier(for: category)
        let baseReward = Currency.rounded(amount * multiplier * card.pointValue)
        components.append(
            RewardComponent(
                kind: .baseReward,
                label: "\(card.rateDescription(for: category)) on \(Currency.string(amount))",
                amount: baseReward
            )
        )

        let offers = merchantProvider.offers.filter {
            $0.cardID == card.id && $0.merchantID == merchantID
        }

        var offerRequiringActivation: CardOffer?
        for offer in offers {
            let uncapped = Currency.rounded(offer.kind.uncappedValue(for: amount))
            let capped = Currency.rounded(offer.cappedValue(for: amount))

            components.append(
                RewardComponent(
                    kind: .merchantOffer,
                    label: "\(offer.shortDescription) at this merchant",
                    amount: uncapped
                )
            )

            // The cap is shown as its own negative line so the advertised offer
            // value stays visible and the arithmetic still balances.
            let adjustment = capped - uncapped
            if adjustment != 0 {
                components.append(
                    RewardComponent(
                        kind: .capAdjustment,
                        label: "Capped at \(Currency.string(offer.maximumValue ?? capped))",
                        amount: adjustment
                    )
                )
            }

            if offer.requiresActivation && offerRequiringActivation == nil {
                offerRequiringActivation = offer
            }
        }

        let program = merchantProvider.diningProgram
        if program.isEligible(merchantID: merchantID) {
            let value = Currency.rounded(program.value(for: amount, merchantID: merchantID))
            if value != 0 {
                let miles = program.miles(for: amount, merchantID: merchantID)
                let milesText = miles.formatted(.number.precision(.fractionLength(0...2)))
                components.append(
                    RewardComponent(
                        kind: .diningProgram,
                        label: "\(milesText) airline miles at \(Currency.rateString(program.mileValue)) each",
                        amount: value
                    )
                )
            }
        }

        if includeAnnualFeeInValue && card.annualFee != 0 {
            components.append(
                RewardComponent(
                    kind: .fee,
                    label: "\(card.name) annual fee",
                    amount: -Currency.rounded(card.annualFee)
                )
            )
        }

        let total = components.reduce(Decimal.zero) { $0 + $1.amount }

        return CardEvaluation(
            card: card,
            components: components,
            totalValue: Currency.rounded(total),
            offerRequiringActivation: offerRequiringActivation
        )
    }

    // MARK: - Ranking

    /// Ranks by value, then by wallet priority, then by id.
    ///
    /// The two trailing keys make ties resolve identically on every run rather
    /// than depending on the ordering of the input array.
    private static func rank(_ lhs: CardEvaluation, _ rhs: CardEvaluation) -> Bool {
        if lhs.totalValue != rhs.totalValue { return lhs.totalValue > rhs.totalValue }
        if lhs.card.priority != rhs.card.priority { return lhs.card.priority < rhs.card.priority }
        return lhs.card.id < rhs.card.id
    }

    // MARK: - Explanation

    private static let unknownMerchantName = "this restaurant"
    private static let unknownMerchantID = "__unknown__"

    /// Builds a concise, fact-only sentence from the computed values.
    ///
    /// Nothing here is invented: every number comes from the evaluation, which
    /// is what lets the voice agent speak the result verbatim.
    private static func explain(
        winner: CardEvaluation,
        runnerUp: CardEvaluation?,
        merchantName: String
    ) -> String {
        let total = Currency.string(winner.totalValue)
        guard let runnerUp else {
            return "Use your \(winner.card.name) at \(merchantName) for an estimated \(total) in value."
        }

        let advantage = winner.totalValue - runnerUp.totalValue
        guard advantage > 0 else {
            return "Your \(winner.card.name) and \(runnerUp.card.name) are tied at "
                + "\(total) in estimated value at \(merchantName)."
        }

        return "Use your \(winner.card.name) at \(merchantName) for an estimated \(total) in value — "
            + "\(Currency.string(advantage)) more than your \(runnerUp.card.name)."
    }
}
