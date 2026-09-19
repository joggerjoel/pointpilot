import SwiftUI

/// The result screen: the winning card, why it won, and the full breakdown.
struct RecommendationView: View {
    let recommendation: CardRecommendation
    let activatedOfferID: String?
    let onActivate: (String) -> Void
    let onAskAnother: () -> Void

    @State private var isShowingBreakdown = false
    @Environment(\.dismiss) private var dismiss

    private var winner: CardEvaluation { recommendation.winner }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    CardFaceView(card: winner.card)
                    valueSummary
                    comparison
                    explanation
                    breakdown
                    if let offer = winner.offerRequiringActivation {
                        activationSection(offer: offer)
                    }
                    warnings
                    actions
                    demoDisclosure
                }
                .padding(.horizontal, Theme.Spacing.section)
                .padding(.vertical, Theme.Spacing.section)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your best card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { Haptics.success() }
    }

    // MARK: - Value

    private var valueSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Estimated reward value")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Currency.string(winner.totalValue))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Estimated reward value \(Currency.string(winner.totalValue))")
                .accessibilityIdentifier("estimatedValueText")

            Text("at \(recommendation.merchantName) on \(Currency.string(recommendation.amount))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let runnerUp = recommendation.runnerUp {
                let advantage = recommendation.advantageOverRunnerUp
                if advantage > 0 {
                    Label(
                        "\(Currency.string(advantage)) more than your \(runnerUp.card.name)",
                        systemImage: "arrow.up.right.circle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.top, 2)
                } else {
                    Label(
                        "Tied with your \(runnerUp.card.name)",
                        systemImage: "equal.circle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.section)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Comparison

    @ViewBuilder
    private var comparison: some View {
        let others = recommendation.ranked.dropFirst()
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                Text("How the others compare")
                    .font(.headline)

                ForEach(others) { evaluation in
                    HStack {
                        Text(evaluation.card.name)
                            .font(.subheadline)
                        Spacer(minLength: Theme.Spacing.tight)
                        Text(Currency.string(evaluation.totalValue))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(evaluation.card.name), \(Currency.string(evaluation.totalValue))"
                    )

                    if evaluation.id != others.last?.id {
                        Divider()
                    }
                }
            }
            .padding(Theme.Spacing.section)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Why this card?")
                .font(.headline)
            Text(recommendation.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        DisclosureGroup(isExpanded: $isShowingBreakdown) {
            VStack(spacing: 0) {
                ForEach(winner.components) { component in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.kind.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(component.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Theme.Spacing.standard)
                        // Sign and label carry the meaning, never color alone.
                        Text(Currency.signedString(component.amount))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(component.isDeduction ? .secondary : .primary)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                    .accessibilityElement(children: .combine)

                    Divider()
                }

                HStack {
                    Text("Total estimated value")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Currency.string(winner.totalValue))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
                .padding(.top, Theme.Spacing.tight)
                .accessibilityElement(children: .combine)
            }
            .padding(.top, Theme.Spacing.tight)
        } label: {
            Label("See the math", systemImage: "function")
                .font(.headline)
        }
        .accessibilityIdentifier("seeTheMath")
        .padding(Theme.Spacing.section)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Activation

    private func activationSection(offer: CardOffer) -> some View {
        let isActivated = activatedOfferID == offer.id

        return VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("This offer needs activation")
                .font(.headline)

            Text("\(offer.shortDescription) at \(recommendation.merchantName), worth up to "
                + "\(Currency.string(offer.cappedValue(for: recommendation.amount))).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onActivate(offer.id)
            } label: {
                Label(
                    isActivated ? "Activated (simulated)" : "Activate Offer",
                    systemImage: isActivated ? "checkmark.circle.fill" : "bolt.circle"
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.minimumTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isActivated)
            .accessibilityIdentifier("activateOfferButton")

            Text("Demo action — this does not activate anything with your card issuer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.section)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var warnings: some View {
        ForEach(recommendation.warnings, id: \.self) { warning in
            NoticeBanner(text: warning, systemImage: "info.circle", tone: .informational)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        Button {
            onAskAnother()
            dismiss()
        } label: {
            Text("Ask Another")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.minimumTouchTarget)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("askAnotherButton")
    }

    private var demoDisclosure: some View {
        Text("Demo data — sample cards, offers and valuations. Nothing here is financial advice.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    let repository = SampleDataRepository.shared
    let engine = RecommendationEngine(cards: repository.cards, merchantProvider: repository)
    let result = try? engine.recommend(merchantQuery: "Nobu", amount: 200)

    return Group {
        if let result {
            RecommendationView(
                recommendation: result,
                activatedOfferID: nil,
                onActivate: { _ in },
                onAskAnother: {}
            )
        } else {
            Text("Preview unavailable")
        }
    }
}
