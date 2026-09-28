import SwiftUI

/// One fact on a place page: the whisper first, then the whole story and where it comes from.
/// Everything is visible at once; opening the page is already the "tell me more" step.
struct FactCard: View {
    let fact: Fact

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fact.category.label)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                StatusBadge(status: fact.status)
            }

            Text(fact.headline)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(fact.short)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            Text(fact.long)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if fact.status != .fact {
                Label(fact.status.explanation, systemImage: fact.status.symbol)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(fact.status.color)
            }

            SourcesList(sources: fact.sources)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .leading) {
            if fact.status != .fact {
                UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18)
                    .fill(fact.status.color)
                    .frame(width: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        if fact.status == .fact {
            Theme.cardBackground
        } else {
            ZStack {
                Theme.cardBackground
                fact.status.color.opacity(0.07)
            }
        }
    }
}

/// Compact, tappable source links under a fact.
struct SourcesList: View {
    let sources: [Fact.Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sources.count == 1 ? "Source" : "Sources")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                if index > 0 {
                    Divider()
                }
                Link(destination: source.url) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(source.publisher)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(source.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(source.publisher): \(source.title)")
                .accessibilityHint(String(localized: "Opens in your browser"))
                .accessibilityAddTraits(.isLink)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
