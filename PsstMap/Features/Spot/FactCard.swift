import SwiftUI

/// One story on a place page. The whisper comes first in full weight, then the rest of the story,
/// then a single "Sources" menu. Legends and disputes carry their label and a colored rule.
struct FactCard: View {
    let fact: Fact
    var number = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String(format: "%02d", number))
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.secondary)
                Label(fact.category.label, systemImage: fact.category.symbol)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(fact.category.color)
                Spacer(minLength: 0)
                StatusBadge(status: fact.status)
            }
            .accessibilityElement(children: .combine)

            Text(fact.headline)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(fact.short)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            Text(fact.long)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.75))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            if fact.status != .fact {
                Label(fact.status.explanation, systemImage: fact.status.symbol)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(fact.status.color)
                    .padding(.top, 2)
            }

            SourcesMenu(sources: fact.sources)
                .padding(.top, 4)
        }
        .padding(.leading, fact.status == .fact ? 0 : 14)
        .overlay(alignment: .leading) {
            if fact.status != .fact {
                Capsule()
                    .fill(fact.status.color)
                    .frame(width: 3)
            }
        }
    }
}

/// The sources of a story, folded into one small menu so they don't crowd the reading.
struct SourcesMenu: View {
    let sources: [Fact.Source]
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                Button {
                    openURL(source.url)
                } label: {
                    Text(source.publisher)
                    Text(source.title)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                Text(summary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel(String(localized: "Sources: \(summary)"))
        .accessibilityHint(String(localized: "Choose a source to open it"))
    }

    private var summary: String {
        let publishers = sources.map(\.publisher)
        guard let first = publishers.first else { return "" }
        return publishers.count == 1 ? first : String(localized: "\(first) and \(publishers.count - 1) more")
    }
}
