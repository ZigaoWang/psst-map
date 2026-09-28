import SwiftUI

/// One fact: the short version by default, the long version and sources on request.
struct FactCard: View {
    let fact: Fact
    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text(fact.short)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text(fact.long)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    if fact.status != .fact {
                        Label(fact.status.explanation, systemImage: fact.status.symbol)
                            .font(.footnote)
                            .foregroundStyle(fact.status.color)
                    }
                    SourcesList(sources: fact.sources)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Show less" : "Read more")
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityHint(isExpanded ? "" : String(localized: "Shows the full story and its sources"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .leading) {
            if fact.status != .fact {
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                    .fill(fact.status.color)
                    .frame(width: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

struct SourcesList: View {
    let sources: [Fact.Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sources.count == 1 ? "Source" : "Sources")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            ForEach(sources, id: \.url) { source in
                Link(destination: source.url) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(source.publisher)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel("\(source.title), \(source.publisher)")
                .accessibilityHint(String(localized: "Opens in your browser"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
