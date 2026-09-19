import Foundation

/// The spending category a purchase falls into.
enum RewardCategory: String, Codable, CaseIterable, Sendable {
    case dining
    case groceries
    case travel
    case gas
    /// Apparel and general retail. Named to match how issuers market it.
    case clothing
    case entertainment
    case other

    var displayName: String {
        switch self {
        case .dining: return "Dining"
        case .groceries: return "Groceries"
        case .travel: return "Travel"
        case .gas: return "Gas"
        case .clothing: return "Shopping"
        case .entertainment: return "Entertainment"
        case .other: return "Everything else"
        }
    }
}

/// The kind of line item in a reward calculation.
///
/// Every component is a signed dollar amount so the breakdown can be shown
/// directly to the user: positive components add value, negative ones reduce it.
enum RewardComponentKind: String, Codable, Sendable {
    case baseReward
    case merchantOffer
    case diningProgram
    case capAdjustment
    case fee

    var displayName: String {
        switch self {
        case .baseReward: return "Card rewards"
        case .merchantOffer: return "Merchant offer"
        case .diningProgram: return "Airline dining rewards"
        case .capAdjustment: return "Offer cap adjustment"
        case .fee: return "Fee"
        }
    }
}

/// A single, individually explainable line item of a recommendation.
struct RewardComponent: Identifiable, Hashable, Sendable {
    let kind: RewardComponentKind
    /// Human-readable detail, e.g. "4× points on $200.00".
    let label: String
    /// Signed dollar value of this component.
    let amount: Decimal

    var id: String { "\(kind.rawValue)::\(label)" }

    init(kind: RewardComponentKind, label: String, amount: Decimal) {
        self.kind = kind
        self.label = label
        self.amount = amount
    }

    /// Whether this component should be presented as a deduction.
    var isDeduction: Bool { amount < 0 }
}

/// Currency helpers. `Decimal` is used everywhere so money never goes through
/// binary floating point.
enum Currency {
    /// The number of fraction digits used for every displayed and stored amount.
    static let fractionDigits = 2

    /// Rounds a decimal to cents using the plain (half-up) rule so results are
    /// stable and predictable for display and comparison.
    static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, fractionDigits, .plain)
        return result
    }

    /// Formats an amount as US dollars with exactly two fraction digits.
    static func string(_ value: Decimal) -> String {
        rounded(value).formatted(
            .currency(code: "USD").precision(.fractionLength(fractionDigits))
        )
    }

    /// Formats an amount as a signed value, e.g. "−$20.00".
    static func signedString(_ value: Decimal) -> String {
        let magnitude = string(abs(value))
        if value < 0 { return "−\(magnitude)" }
        if value > 0 { return "+\(magnitude)" }
        return magnitude
    }

    /// Formats a per-point or per-mile valuation.
    ///
    /// These need more precision than a cash amount: $0.015 per mile must not
    /// display as "$0.02 each", or the stated rate would contradict the total
    /// the same screen shows.
    static func rateString(_ value: Decimal) -> String {
        value.formatted(
            .currency(code: "USD").precision(.fractionLength(2...4))
        )
    }

    /// Formats a loyalty multiplier, e.g. "4×".
    static func multiplierString(_ value: Decimal) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
