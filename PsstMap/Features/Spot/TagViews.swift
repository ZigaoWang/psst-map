import SwiftUI

/// How tags look and read, shared by chips, rows, and the thread view.
enum TagStyle {
    static func symbol(for type: String) -> String {
        switch type {
        case "person_or_group": "person.2"
        case "event": "calendar"
        case "era": "hourglass"
        case "movement": "paintpalette"
        default: "number"
        }
    }

    static func typeLabel(_ type: String) -> String {
        switch type {
        case "person_or_group": String(localized: "Person or group")
        case "event": String(localized: "Event")
        case "era": String(localized: "Era")
        case "movement": String(localized: "Movement")
        default: String(localized: "Theme")
        }
    }

    /// The tag's name in the reader's language when one is known, else its English name.
    static func name(of tag: Tag) -> String {
        Place.lookup(Locale.preferredLanguages.first ?? "en", in: tag.names) ?? tag.name
    }
}

/// The tags on a story, as a row of small chips. Each opens its thread.
struct TagChips: View {
    let tagIDs: [String]
    @Environment(AppModel.self) private var app

    var body: some View {
        let tags = tagIDs.compactMap { app.catalog.tag(id: $0) }
        if !tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
                    NavigationLink(value: tag) {
                        Text(TagStyle.name(of: tag))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(String(localized: "Thread: \(TagStyle.name(of: tag))"))
                    .accessibilityHint(String(localized: "Shows every place connected by it"))
                }
            }
        }
    }
}

/// Every place connected by one tag, grouped by city.
struct TagPlacesView: View {
    let tag: Tag
    @Environment(AppModel.self) private var app

    var body: some View {
        let places = app.catalog.places(tagged: tag.id)
        let byCity = Dictionary(grouping: places, by: \.city)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(TagStyle.typeLabel(tag.type), systemImage: TagStyle.symbol(for: tag.type))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(TagStyle.name(of: tag))
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(places.count == 1 ? "1 place" : "\(places.count) places")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            ForEach(byCity.keys.sorted(), id: \.self) { city in
                Section(city) {
                    ForEach(byCity[city] ?? []) { place in
                        NavigationLink(value: place) {
                            TagPlaceRow(place: place, tagID: tag.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TagPlaceRow: View {
    let place: Place
    let tagID: String

    var body: some View {
        HStack(spacing: 12) {
            PlaceThumbnail(place: place)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text.story((place.spot.facts.first { $0.tags.contains(tagID) } ?? place.leadFact).headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A thread opened from search: its own navigation, so places can open inside it.
struct TagSheet: View {
    let tag: Tag
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TagPlacesView(tag: tag)
                .navigationDestination(for: Place.self) { PlacePage(place: $0, showsMapButton: true) }
                .navigationDestination(for: Tag.self) { TagPlacesView(tag: $0) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Lays out chips left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
