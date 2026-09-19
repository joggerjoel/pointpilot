import SwiftUI

/// The rewards dashboard.
///
/// Everything here is derived from `MetricsSummary`, which is computed from the
/// same engine the recommendation flow uses — so the totals shown match what the
/// app would tell you at the register. All figures are demo data and the screen
/// says so.
struct MetricsView: View {
    let metrics: MetricsSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                headline
                missedValueCard
                if !metrics.standings.isEmpty {
                    leaderboard
                }
                if !metrics.categoryBreakdown.isEmpty {
                    categorySection
                }
                activitySection
                demoDisclosure
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.vertical, Theme.Spacing.section)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your rewards")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("metricsScreen")
    }

    // MARK: - Headline

    private var headline: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Earned in the last 30 days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                CountUpCurrencyText(value: metrics.totalEarned, color: .green)
                    .accessibilityLabel(
                        "Earned in the last 30 days \(Currency.string(metrics.totalEarned))"
                    )
                    .accessibilityIdentifier("metricsTotalEarned")

                HStack(spacing: Theme.Spacing.tight) {
                    Text("on \(Currency.string(metrics.totalSpent)) of tracked spend")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(metrics.effectiveRate)% back")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Missed value

    private var missedValueCard: some View {
        SoftCard {
            HStack(alignment: .top, spacing: Theme.Spacing.standard) {
                IllustrationView(subject: .generic, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Left on the table")
                        .font(.subheadline.weight(.semibold))
                    Text(Currency.string(metrics.missedValue))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("metricsMissedValue")
                    Text("You'd have earned this much more by using the card we recommended "
                        + "on every purchase.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("Card leaderboard")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(metrics.standings.enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: Theme.Spacing.standard) {
                        // Rank is stated in text, not implied by position alone.
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .center)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(hex: standing.cardAccentHex))
                            .frame(width: 34, height: 22)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(standing.cardName)
                                .font(.subheadline.weight(.medium))
                            Text("\(standing.uses) purchase\(standing.uses == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(Currency.string(standing.earned))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Rank \(index + 1), \(standing.cardName), "
                            + "\(standing.uses) purchases, earned "
                            + "\(Currency.string(standing.earned))"
                    )

                    if index < metrics.standings.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("Where you spent")
                .font(.headline)

            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                ForEach(metrics.categoryBreakdown, id: \.category) { item in
                    let largest = metrics.categoryBreakdown.first?.amount ?? 1
                    // Fraction drives the bar's length only; the amount is
                    // always spelled out beside it.
                    let fraction = largest > 0
                        ? NSDecimalNumber(decimal: item.amount).doubleValue
                            / NSDecimalNumber(decimal: largest).doubleValue
                        : 0

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.category.displayName)
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: Theme.Spacing.tight)
                            Text(Currency.string(item.amount))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        MetricBar(
                            fraction: fraction,
                            tint: Color(hex: Self.tintHex(for: item.category))
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(item.category.displayName), \(Currency.string(item.amount))"
                    )
                }
            }
            .padding(Theme.Spacing.section)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private static func tintHex(for category: RewardCategory) -> String {
        switch category {
        case .dining: return "#C97B4A"
        case .groceries: return "#5F9E6B"
        case .travel: return "#5B87BE"
        case .gas: return "#C98E3F"
        case .clothing: return "#B2638E"
        case .entertainment: return "#8362B0"
        case .other: return "#6E7F96"
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("Activity")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(metrics.recentEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: Theme.Spacing.standard) {
                        IllustrationView(
                            subject: IllustrationSubject.forCategory(entry.category),
                            size: 40
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.merchantName)
                                .font(.subheadline.weight(.medium))
                            Text("\(entry.usedCardName) · \(entry.daysAgo)d ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Currency.string(entry.earned))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                            if entry.usedSuboptimalCard {
                                // The missed amount is signed and spelled out,
                                // never implied by a colour shift alone.
                                Text("\(Currency.string(entry.missedValue)) missed")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                    .accessibilityElement(children: .combine)

                    if index < metrics.recentEntries.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var demoDisclosure: some View {
        Text("Demo data — sample cards, offers and purchase history. Nothing here is financial advice.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    NavigationStack {
        MetricsView(metrics: SampleDataRepository.shared.metrics)
    }
}
