import SwiftUI

/// Motion and haptics that make the app feel alive without getting in the way.
///
/// Delight here is deliberately cheap and interruptible: spring transitions,
/// counted-up numbers and a single success haptic. Nothing animates for longer
/// than a moment, and every animation is suppressed when the system asks for
/// reduced motion.
enum Delight {
    /// The house spring. Slightly under-damped so cards settle with a bit of life.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    /// A quicker spring for small state flips like chip selection.
    static let quickSpring = Animation.spring(response: 0.28, dampingFraction: 0.7)

    /// Stagger for lists of cards, so they arrive in sequence rather than at once.
    static func stagger(_ index: Int) -> Animation {
        spring.delay(Double(index) * 0.06)
    }
}

/// A currency figure that counts up to its value on appear.
///
/// The animation drives a 0…1 progress value rather than the `Decimal` itself,
/// because SwiftUI cannot interpolate `Decimal` — money must never be animated
/// through binary floating point, so the interpolation happens on a plain
/// scalar and only the final formatting touches the decimal value.
struct CountUpCurrencyText: View {
    let value: Decimal
    var font: Font = .system(.largeTitle, design: .rounded).weight(.bold)
    var color: Color = .primary

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayed: Decimal {
        // Integer literal and Double scaling only; the rounded result is what
        // the user reads, and rounding happens once at format time.
        value * Decimal(progress)
    }

    var body: some View {
        Text(Currency.string(displayed))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear {
                guard !reduceMotion else {
                    progress = 1
                    return
                }
                withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
            }
    }
}

/// A soft, dimensional container used for the home screen's feature cards.
///
/// One place defines the surface treatment — radius, fill, hairline border and
/// shadow — so every card on the home screen matches without each call site
/// re-specifying its own.
struct SoftCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.section
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}

/// A horizontally filled progress bar used by the metrics breakdown.
///
/// The numeric value is always stated in text beside the bar, so the
/// information is never carried by length or colour alone.
struct MetricBar: View {
    /// 0…1 fraction of the largest value in the group.
    let fraction: Double
    let tint: Color

    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * CGFloat(grown ? max(0.02, fraction) : 0))
            }
        }
        .frame(height: 10)
        .onAppear {
            guard !reduceMotion else {
                grown = true
                return
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { grown = true }
        }
    }
}

#Preview("Delight") {
    VStack(spacing: 24) {
        CountUpCurrencyText(value: 45)
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Soft card").font(.headline)
                Text("A calm surface with depth.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        MetricBar(fraction: 0.62, tint: .green)
            .padding(.horizontal)
    }
    .padding()
}
