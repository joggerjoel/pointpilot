import SwiftUI

/// The app's illustration language, drawn entirely in SwiftUI.
///
/// Illustrations are built from shapes and gradients rather than shipped as
/// bitmaps: they stay crisp at every size, follow Dark Mode automatically, add
/// nothing to the bundle, and never need a @2x/@3x export. The visual grammar is
/// deliberately soft and dimensional — a tinted ground, one large low-contrast
/// blob for depth, and a single crisp glyph as the focal point.
enum IllustrationSubject: String, CaseIterable, Sendable {
    case dining
    case coffee
    case groceries
    case travel
    case flights
    case gas
    case shopping
    case entertainment
    case generic

    /// The focal glyph. Chosen so the subject reads instantly at a glance.
    var symbolName: String {
        switch self {
        case .dining: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .groceries: return "cart.fill"
        case .travel: return "suitcase.rolling.fill"
        case .flights: return "airplane.departure"
        case .gas: return "fuelpump.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "ticket.fill"
        case .generic: return "sparkles"
        }
    }

    /// Two-stop tint. Kept warm and desaturated so illustrations sit behind
    /// content without competing with the card faces.
    var tints: [Color] {
        switch self {
        case .dining: return [Color(hex: "#E8B27D"), Color(hex: "#C97B4A")]
        case .coffee: return [Color(hex: "#C9A17E"), Color(hex: "#8C6244")]
        case .groceries: return [Color(hex: "#A8CFA0"), Color(hex: "#5F9E6B")]
        case .travel: return [Color(hex: "#9FC4E8"), Color(hex: "#5B87BE")]
        case .flights: return [Color(hex: "#A6B4E8"), Color(hex: "#5F6FBF")]
        case .gas: return [Color(hex: "#F0C48A"), Color(hex: "#C98E3F")]
        case .shopping: return [Color(hex: "#E4A9C4"), Color(hex: "#B2638E")]
        case .entertainment: return [Color(hex: "#C2A8E0"), Color(hex: "#8362B0")]
        case .generic: return [Color(hex: "#A9B6C9"), Color(hex: "#6E7F96")]
        }
    }

    /// Best-effort mapping from a spending category, so a merchant always has a
    /// sensible illustration without every call site choosing one by hand.
    ///
    /// Lives here rather than on `RewardCategory` so the model layer stays free
    /// of SwiftUI types.
    static func forCategory(_ category: RewardCategory) -> IllustrationSubject {
        switch category {
        case .dining: return .dining
        case .groceries: return .groceries
        case .travel: return .travel
        case .gas: return .gas
        case .clothing: return .shopping
        case .entertainment: return .entertainment
        case .other: return .generic
        }
    }
}

/// An organic blob used as the soft depth layer behind a glyph.
///
/// Built from four cubic curves with a continuous corner feel, so it reads as a
/// hand-drawn smear rather than a circle or an ellipse.
struct SoftBlob: Shape {
    /// Rotates the control points so stacked blobs do not look identical.
    var variance: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        // Radii wobble slightly by variance to keep the silhouette irregular.
        // Trigonometry is done in Double: CGFloat's sin/cos overloads are not
        // available on every platform this file could be compiled for.
        let v = Double(variance)
        let rx = w * CGFloat(0.46 + 0.04 * sin(v))
        let ry = h * CGFloat(0.44 + 0.05 * cos(v * 1.3))

        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - ry))
        path.addCurve(
            to: CGPoint(x: cx + rx, y: cy),
            control1: CGPoint(x: cx + rx * 0.78, y: cy - ry * 0.92),
            control2: CGPoint(x: cx + rx * 0.98, y: cy - ry * 0.42)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: cy + ry),
            control1: CGPoint(x: cx + rx * 0.96, y: cy + ry * 0.48),
            control2: CGPoint(x: cx + rx * 0.72, y: cy + ry * 0.94)
        )
        path.addCurve(
            to: CGPoint(x: cx - rx, y: cy),
            control1: CGPoint(x: cx - rx * 0.7, y: cy + ry * 0.95),
            control2: CGPoint(x: cx - rx * 0.97, y: cy + ry * 0.4)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: cy - ry),
            control1: CGPoint(x: cx - rx * 0.95, y: cy - ry * 0.45),
            control2: CGPoint(x: cx - rx * 0.75, y: cy - ry * 0.9)
        )
        path.closeSubpath()
        return path
    }
}

/// A single soft illustration: tinted ground, blob depth, crisp glyph.
struct IllustrationView: View {
    let subject: IllustrationSubject
    var size: CGFloat = 96
    /// When true the subject is decorative and hidden from VoiceOver.
    var isDecorative: Bool = true

    private var tints: [Color] { subject.tints }

    var body: some View {
        ZStack {
            // Ground: a gentle wash that keeps the glyph readable on any surface.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tints[0].opacity(0.30), tints[1].opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Depth: two offset blobs, light over dark, to imply dimension.
            SoftBlob(variance: 1.1)
                .fill(tints[1].opacity(0.28))
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(x: -size * 0.05, y: size * 0.06)
                .blur(radius: size * 0.045)

            SoftBlob(variance: 2.4)
                .fill(
                    LinearGradient(
                        colors: [tints[0].opacity(0.85), tints[1].opacity(0.70)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.62, height: size * 0.62)

            // Focal glyph, with a soft drop shadow to lift it off the blob.
            Image(systemName: subject.symbolName)
                .font(.system(size: size * 0.30, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: tints[1].opacity(0.45), radius: size * 0.05, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(isDecorative)
    }
}

#Preview("Illustrations") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 20) {
            ForEach(IllustrationSubject.allCases, id: \.self) { subject in
                VStack(spacing: 8) {
                    IllustrationView(subject: subject)
                    Text(subject.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
