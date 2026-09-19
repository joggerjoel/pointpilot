import Foundation

/// A credit card in the user's wallet.
///
/// All sample cards are fictional stand-ins for the demo and are not affiliated
/// with any issuer.
struct CreditCard: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let issuer: String
    /// What the card earns: "points" or "miles".
    let rewardUnitName: String
    /// Category multipliers, expressed as points/miles earned per dollar.
    let multipliers: [RewardCategory: Decimal]
    /// Multiplier applied to any category not listed in `multipliers`.
    let defaultMultiplier: Decimal
    /// Estimated dollar value of a single point or mile.
    let pointValue: Decimal
    /// Annual fee, used for the fee line item when a card is evaluated.
    let annualFee: Decimal
    /// Wallet order. Also the deterministic tie-breaker when two cards tie.
    let priority: Int
    /// Accent color used to render the card. Kept as a hex string so the model
    /// layer has no dependency on SwiftUI.
    let accentHex: String

    /// The multiplier this card earns in a given category.
    func multiplier(for category: RewardCategory) -> Decimal {
        multipliers[category] ?? defaultMultiplier
    }

    /// Short label for the reward rate, e.g. "4× points on dining".
    func rateDescription(for category: RewardCategory) -> String {
        let multiplier = multiplier(for: category)
        return "\(Currency.multiplierString(multiplier)) \(rewardUnitName) on \(category.displayName.lowercased())"
    }
}

/// How a merchant offer pays out.
enum OfferKind: Hashable, Sendable {
    /// A percentage of the purchase amount, expressed as a fraction (0.10 == 10%).
    case percentage(Decimal)
    /// A flat dollar amount.
    case flatCash(Decimal)

    /// The uncapped dollar value of this offer for a given purchase amount.
    func uncappedValue(for amount: Decimal) -> Decimal {
        switch self {
        case .percentage(let rate):
            return amount * rate
        case .flatCash(let value):
            return value
        }
    }

    /// Short human-readable description, e.g. "10% back" or "$5 back".
    var shortDescription: String {
        switch self {
        case .percentage(let rate):
            let percent = (rate * 100).formatted(.number.precision(.fractionLength(0...2)))
            return "\(percent)% back"
        case .flatCash(let value):
            return "\(Currency.string(value)) back"
        }
    }
}

/// A card-linked merchant offer.
struct CardOffer: Identifiable, Hashable, Sendable {
    let id: String
    let cardID: String
    let merchantID: String
    let kind: OfferKind
    /// Maximum dollar value the offer can pay out. `nil` means uncapped.
    let maximumValue: Decimal?
    /// Whether the offer has to be activated before it applies.
    let requiresActivation: Bool

    var shortDescription: String { kind.shortDescription }

    /// The dollar value of this offer for a purchase, after applying the cap.
    func cappedValue(for amount: Decimal) -> Decimal {
        let uncapped = kind.uncappedValue(for: amount)
        guard let maximumValue else { return uncapped }
        return min(uncapped, maximumValue)
    }
}

/// An airline dining program that earns airline miles on top of card rewards.
///
/// The program is a property of the restaurant rather than the card, so it
/// applies identically to every card evaluated for an eligible merchant.
struct DiningProgram: Hashable, Sendable {
    let id: String
    let name: String
    /// Airline miles earned per dollar spent.
    let milesPerDollar: Decimal
    /// Estimated dollar value of a single airline mile.
    let mileValue: Decimal
    /// Merchants participating in the program.
    let eligibleMerchantIDs: Set<String>

    func isEligible(merchantID: String) -> Bool {
        eligibleMerchantIDs.contains(merchantID)
    }

    /// Dollar value of the airline miles earned at a given merchant.
    func value(for amount: Decimal, merchantID: String) -> Decimal {
        guard isEligible(merchantID: merchantID) else { return 0 }
        return amount * milesPerDollar * mileValue
    }

    /// The miles earned at a given merchant, for display.
    func miles(for amount: Decimal, merchantID: String) -> Decimal {
        guard isEligible(merchantID: merchantID) else { return 0 }
        return amount * milesPerDollar
    }
}
