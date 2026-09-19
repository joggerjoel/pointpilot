import Foundation

/// One past recommendation, kept so the dashboard can show totals.
///
/// These are demo aggregates: the app has no account, no bank connection and no
/// server, so the history is a fixed sample set rather than a record of the
/// user's real spending. It is labelled as demo data wherever it is shown.
struct HistoryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let merchantName: String
    let category: RewardCategory
    /// What was spent.
    let amount: Decimal
    /// The card the user actually used.
    let usedCardID: String
    let usedCardName: String
    /// Value actually earned on this purchase, as the engine computes it.
    let earned: Decimal
    /// The best value available in the wallet. Equal to `earned` when the user
    /// took the recommendation; greater when a weaker card was used.
    let bestPossible: Decimal
    /// How long ago the purchase happened, in days.
    let daysAgo: Int

    /// Value left behind by not using the best card.
    var missedValue: Decimal { max(0, bestPossible - earned) }

    /// True when a better card existed and was not used.
    var usedSuboptimalCard: Bool { missedValue > 0 }
}

/// Aggregated dashboard figures derived from a list of history entries.
///
/// Pure value type with no I/O, so the arithmetic is testable on fixed fixtures
/// and the view stays declarative.
struct MetricsSummary: Hashable, Sendable {
    struct CardStanding: Identifiable, Hashable, Sendable {
        let cardID: String
        let cardName: String
        let cardAccentHex: String
        let earned: Decimal
        let uses: Int

        var id: String { cardID }
    }

    let entries: [HistoryEntry]

    init(entries: [HistoryEntry]) {
        // Newest first so "this month" and the activity list agree on ordering.
        self.entries = entries.sorted { $0.daysAgo < $1.daysAgo }
    }

    /// Entries inside the trailing 30-day window the dashboard calls "this month".
    var recentEntries: [HistoryEntry] { entries.filter { $0.daysAgo <= 30 } }

    var totalEarned: Decimal {
        recentEntries.reduce(Decimal.zero) { $0 + $1.earned }
    }

    var totalSpent: Decimal {
        recentEntries.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// The "money left on the table" figure: value given up by using a card
    /// other than the one the engine would have recommended.
    var missedValue: Decimal {
        recentEntries.reduce(Decimal.zero) { $0 + $1.missedValue }
    }

    /// Effective return across all tracked spend, as a percentage (1.4 == 1.4%).
    var effectiveRate: Decimal {
        guard totalSpent > 0 else { return 0 }
        return Currency.rounded(totalEarned / totalSpent * 100)
    }

    /// Cards ranked by value earned, highest first. Ties break on use count,
    /// then name, so the order is stable across renders.
    var standings: [CardStanding] {
        var earnedByCard: [String: Decimal] = [:]
        var usesByCard: [String: Int] = [:]
        var nameByCard: [String: String] = [:]

        for entry in recentEntries {
            earnedByCard[entry.usedCardID, default: 0] += entry.earned
            usesByCard[entry.usedCardID, default: 0] += 1
            nameByCard[entry.usedCardID] = entry.usedCardName
        }

        return earnedByCard
            .map { cardID, earned in
                CardStanding(
                    cardID: cardID,
                    cardName: nameByCard[cardID] ?? cardID,
                    cardAccentHex: Self.accentHex(forCardID: cardID),
                    earned: earned,
                    uses: usesByCard[cardID] ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.earned != rhs.earned { return lhs.earned > rhs.earned }
                if lhs.uses != rhs.uses { return lhs.uses > rhs.uses }
                return lhs.cardName < rhs.cardName
            }
    }

    /// The card earning the most across the window, or nil when there is no history.
    var topCard: CardStanding? { standings.first }

    /// Spend grouped by category, largest first — drives the breakdown bars.
    var categoryBreakdown: [(category: RewardCategory, amount: Decimal)] {
        var totals: [RewardCategory: Decimal] = [:]
        for entry in recentEntries {
            totals[entry.category, default: 0] += entry.amount
        }
        return totals
            .map { (category: $0.key, amount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.category.rawValue < rhs.category.rawValue
            }
    }

    /// Accent color for a card, so the dashboard can render it consistently
    /// with the wallet without depending on the repository.
    private static func accentHex(forCardID cardID: String) -> String {
        switch cardID {
        case SampleDataRepository.amexGoldID: return "#B99A5B"
        case SampleDataRepository.sapphirePreferredID: return "#2F6BA8"
        case SampleDataRepository.ventureID: return "#8C2F39"
        default: return "#6E7F96"
        }
    }
}
