import SwiftUI

/// The app's front door.
///
/// Modelled on the "one obvious next action" layout: a greeting, a hero card
/// that states what the app is for, then a short list of things the user can do.
/// Everything below the fold is secondary and can be scrolled past.
struct HomeView: View {
    let viewModel: AskViewModel
    let onFindCard: () -> Void
    let onShowMetrics: () -> Void
    let onShowWallet: () -> Void

    private var metrics: MetricsSummary { viewModel.repository.metrics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                greeting
                hero
                actionRows
                statsStrip
                if !metrics.recentEntries.isEmpty {
                    recentActivity
                }
                demoDisclosure
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.bottom, Theme.Spacing.loose)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("homeScreen")
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(Self.timeOfDayGreeting())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("How can I help you today?")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.standard)
        .accessibilityElement(children: .combine)
    }

    /// A greeting that matches the clock, so the app feels current without
    /// claiming to know anything about the user.
    private static func timeOfDayGreeting(now: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Hero

    private var hero: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                HStack(alignment: .top, spacing: Theme.Spacing.standard) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        Text("Pick the right card")
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Tell me where you are and what you'll spend.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    IllustrationView(subject: .dining, size: 84)
                }

                Button {
                    Haptics.impact()
                    onFindCard()
                } label: {
                    Label("Find my best card", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.minimumTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("homeFindCardButton")
                .accessibilityHint("Opens the card finder")
            }
        }
    }

    // MARK: - Action rows

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("I want to…")
                .font(.headline)

            VStack(spacing: 0) {
                actionRow(
                    title: "See my rewards",
                    subtitle: "What you've earned and missed",
                    subject: .generic,
                    identifier: "homeRewardsRow",
                    action: onShowMetrics
                )
                Divider().padding(.leading, 76)
                actionRow(
                    title: "My wallet",
                    subtitle: "\(viewModel.cards.count) cards in your wallet",
                    subject: .shopping,
                    identifier: "homeWalletRow",
                    action: onShowWallet
                )
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func actionRow(
        title: String,
        subtitle: String,
        subject: IllustrationSubject,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact()
            action()
        } label: {
            HStack(spacing: Theme.Spacing.standard) {
                IllustrationView(subject: subject, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.standard)
            .frame(minHeight: Theme.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: - Stats

    private var statsStrip: some View {
        HStack(spacing: Theme.Spacing.standard) {
            statTile(
                caption: "Earned",
                value: Currency.string(metrics.totalEarned),
                tint: .green,
                identifier: "homeEarnedStat"
            )
            statTile(
                caption: "Missed",
                value: Currency.string(metrics.missedValue),
                tint: .orange,
                identifier: "homeMissedStat"
            )
        }
    }

    private func statTile(
        caption: String,
        value: String,
        tint: Color,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Recent activity

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("Recent")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(metrics.recentEntries.prefix(3).enumerated()), id: \.element.id) { index, entry in
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

                        Text(Currency.string(entry.earned))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(entry.merchantName), \(entry.usedCardName), "
                            + "earned \(Currency.string(entry.earned)), \(entry.daysAgo) days ago"
                    )

                    if index < min(3, metrics.recentEntries.count) - 1 {
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
        HomeView(
            viewModel: AskViewModel(
                engine: RecommendationEngine(
                    cards: SampleDataRepository.shared.cards,
                    merchantProvider: SampleDataRepository.shared
                ),
                repository: .shared,
                voiceService: MockVoiceAgentService(),
                voiceIsConfigured: false
            ),
            onFindCard: {},
            onShowMetrics: {},
            onShowWallet: {}
        )
    }
}
