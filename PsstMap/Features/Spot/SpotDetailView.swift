import MapKit
import SwiftUI

/// Everything about one place: its picture, its facts, and what you can do with it.
struct SpotDetailView: View {
    let place: Place
    /// Hidden when the detail is already shown over the map.
    var showsMapButton = true
    var onClose: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SpotVisualView(place: place)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                actions
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                VStack(spacing: 12) {
                    ForEach(place.spot.facts) { fact in
                        FactCard(fact: fact)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
            }
        }
        .background(Theme.screenBackground)
        .overlay(alignment: .topTrailing) {
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .floatingSurface(in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 24)
            .accessibilityLabel(String(localized: "Close"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                KindBadge(kind: place.spot.kind)
                Text("\(place.areaName), \(place.city)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(place.name)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let local = place.spot.localName {
                Text(local)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var actions: some View {
        let isSaved = app.saved.contains(place.id)
        return HStack(spacing: 10) {
            ActionButton(title: isSaved ? String(localized: "Saved") : String(localized: "Save"),
                         symbol: isSaved ? "bookmark.fill" : "bookmark") {
                app.saved.toggle(place.id)
            }
            .sensoryFeedback(.selection, trigger: isSaved)
            .accessibilityAddTraits(isSaved ? .isSelected : [])

            if showsMapButton {
                ActionButton(title: String(localized: "Map"), symbol: "map") {
                    dismiss()
                    app.showOnMap(place)
                }
            }

            ShareLink(item: ShareText.text(for: place)) {
                ActionLabel(title: String(localized: "Share"), symbol: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            ActionButton(title: String(localized: "Directions"), symbol: "arrow.triangle.turn.up.right.diamond") {
                openInMaps()
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = place.spot.coordinateSource.url {
                Link(destination: url) {
                    Text(place.spot.coordinateSource.type == .wikidata
                         ? "Location from Wikidata"
                         : "Location from OpenStreetMap contributors")
                        .underline()
                }
            }
            Text("Spotted something wrong? Every fact links to its sources above.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func openInMaps() {
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            let location = CLLocation(latitude: place.mapCoordinate.latitude, longitude: place.mapCoordinate.longitude)
            item = MKMapItem(location: location, address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: place.mapCoordinate))
        }
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(height: 24)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum ShareText {
    static func text(for place: Place) -> String {
        let fact = place.leadFact
        let note: String = switch fact.status {
        case .fact: ""
        case .legend: "\n" + String(localized: "(A legend, not a proven fact.)")
        case .disputed: "\n" + String(localized: "(Disputed: sources disagree.)")
        }
        return "\(place.name), \(place.city)\n\n\(fact.short)\(note)\n\n" + String(localized: "Found on Psst")
    }
}
