import SwiftUI

/// The read-only wallet. Cards come from the shared sample repository.
struct WalletView: View {
    let repository: SampleDataRepository
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(repository.cards) { card in
                        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                            CardFaceView(card: card)

                            VStack(alignment: .leading, spacing: 4) {
                                detailRow(
                                    "Dining",
                                    card.rateDescription(for: .dining)
                                )
                                detailRow(
                                    "Everything else",
                                    "\(Currency.multiplierString(card.defaultMultiplier)) "
                                        + card.rewardUnitName
                                )
                                detailRow(
                                    "\(card.rewardUnitName.capitalized) value",
                                    "\(Currency.rateString(card.pointValue)) each"
                                )
                                if let offer = offerSummary(for: card) {
                                    detailRow("Merchant offer", offer)
                                }
                            }
                        }
                        .padding(.vertical, Theme.Spacing.tight)
                    }
                } header: {
                    Text("Your cards")
                } footer: {
                    Text("Demo data — sample cards and offers. Read-only in this MVP, and not "
                        + "affiliated with any card issuer.")
                }

                Section("Airline dining program") {
                    let program = repository.diningProgram
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(Currency.multiplierString(program.milesPerDollar)) miles per dollar at "
                            + "participating restaurants, worth "
                            + "\(Currency.rateString(program.mileValue)) per mile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.Spacing.standard)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Describes this card's best merchant offer, if it has one.
    private func offerSummary(for card: CreditCard) -> String? {
        guard let offer = repository.offers.first(where: { $0.cardID == card.id }),
              let merchant = repository.merchant(id: offer.merchantID)
        else { return nil }

        var text = "\(offer.shortDescription) at \(merchant.name)"
        if let maximum = offer.maximumValue {
            text += ", up to \(Currency.string(maximum))"
        }
        return text
    }
}

#Preview {
    WalletView(repository: .shared)
}
