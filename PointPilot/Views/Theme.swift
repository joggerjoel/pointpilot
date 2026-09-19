import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A single place for the app's visual language, so every screen stays
/// consistent instead of each view inventing its own spacing and radius.
enum Theme {
    enum Spacing {
        static let tight: CGFloat = 8
        static let standard: CGFloat = 16
        static let section: CGFloat = 24
        static let loose: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 14
    }

    /// Minimum touch target that satisfies accessibility guidance.
    static let minimumTouchTarget: CGFloat = 44
}

/// Success and impact haptics, wrapped so call sites stay readable and the
/// app still compiles for platforms without UIKit.
enum Haptics {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

/// Renders a card as a native-feeling, restrained card face.
///
/// The styling is deliberately generic and uses only the sample accent color —
/// it does not reproduce any real issuer's trade dress.
struct CardFaceView: View {
    let card: CreditCard
    var isCompact: Bool = false

    private var accent: Color { Color(hex: card.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack {
                Text(card.name)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(.white)
                Spacer(minLength: Theme.Spacing.tight)
                Image(systemName: "creditcard.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
            }

            if !isCompact {
                Text(card.rateDescription(for: .dining).capitalized)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text("Sample card")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(isCompact ? Theme.Spacing.standard : Theme.Spacing.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(card.name), sample card. \(card.rateDescription(for: .dining)). "
                + "Points worth \(Currency.string(card.pointValue)) each."
        )
    }
}

extension Color {
    /// Builds a color from a "#RRGGBB" string, falling back to gray when the
    /// value is malformed rather than crashing.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
