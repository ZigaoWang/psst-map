import SwiftUI

/// A colored chip naming the kind of place, like a line badge on a transit map.
struct KindBadge: View {
    let kind: Spot.Kind
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol)
                .imageScale(.small)
            if !compact {
                Text(kind.label)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(kind.onColor)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .background(kind.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.label)
    }
}

/// Only legends and disputed facts get a badge. Plain facts are the default and stay quiet.
struct StatusBadge: View {
    let status: Fact.Status

    var body: some View {
        if status != .fact {
            Label(status.label, systemImage: status.symbol)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(status.color.opacity(0.5), lineWidth: 1))
                .accessibilityLabel(status == .legend
                                    ? String(localized: "Legend: an unproven story")
                                    : String(localized: "Disputed: sources disagree"))
        }
    }
}

/// The square icon used in lists: the kind's color with its glyph.
struct KindTile: View {
    let kind: Spot.Kind
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(kind.color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(kind.onColor)
            }
            .accessibilityHidden(true)
    }
}

/// Stand-in picture while a visual loads or when none is available.
struct VisualPlaceholder: View {
    let kind: Spot.Kind
    var isLoading = false
    var message: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [kind.color.opacity(0.9), kind.color.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            GridPattern()
                .stroke(kind.onColor.opacity(0.10), lineWidth: 1)
            VStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(kind.onColor.opacity(0.85))
                if isLoading {
                    ProgressView()
                        .tint(kind.onColor)
                } else if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(kind.onColor.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? String(localized: "Loading picture") : (message ?? kind.label))
    }
}

/// A faint street grid, so placeholders read as "map" rather than as an error.
nonisolated struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 28
        var x: CGFloat = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height * 0.6, y: 0))
            x += step * 1.7
        }
        var y: CGFloat = step
        while y < rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y - rect.width * 0.12))
            y += step
        }
        return path
    }
}

extension View {
    /// Floating control background: Liquid Glass on iOS 26, material before that.
    @ViewBuilder
    func floatingSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            // Glass applied to a button's own label swallows its taps, so draw it as a layer behind instead.
            self.background {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .allowsHitTesting(false)
            }
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}

/// The wordmark. The period is part of it.
struct Wordmark: View {
    var size: CGFloat = 44
    var color: Color = Theme.ink

    var body: some View {
        Text("Psst.")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(-0.5)
            .foregroundStyle(color)
            .accessibilityLabel("Psst")
    }
}
