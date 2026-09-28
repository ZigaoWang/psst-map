import MapKit
import SwiftUI

/// Everything about one place: its picture, its facts, and what you can do with it.
struct SpotDetailView: View {
    let place: Place
    /// Hidden when the page was opened from the map already.
    var showsMapButton = true

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showsLookAround = false
    @State private var showsAerial = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SpotHero(place: place, lookAroundScene: lookAroundScene,
                             onLookAround: { showsLookAround = true },
                             onAerial: { showsAerial = true })
                        .frame(height: typeSize.isAccessibilitySize ? 260 : 340)

                    VStack(alignment: .leading, spacing: 22) {
                        header
                        actions
                        VStack(spacing: 14) {
                            ForEach(place.spot.facts) { fact in
                                FactCard(fact: fact)
                            }
                        }
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Theme.screenBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(String(localized: "Close"))
                }
            }
        }
        .lookAroundViewer(isPresented: $showsLookAround, initialScene: lookAroundScene, allowsNavigation: true,
                          showsRoadLabels: true, pointsOfInterest: .excludingAll)
        .fullScreenCover(isPresented: $showsAerial) {
            AerialMapScreen(place: place)
        }
        .task(id: place.id) {
            lookAroundScene = await SpotVisuals.shared.lookAroundScene(for: place)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                KindBadge(kind: place.spot.kind)
                Text("\(place.areaName), \(place.city)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .padding(.horizontal, 4)
    }

    private var actions: some View {
        let isSaved = app.saved.contains(place.id)
        return HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { app.saved.toggle(place.id) }
            } label: {
                Label(isSaved ? String(localized: "Saved") : String(localized: "Save"),
                      systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(isSaved ? Color.primary : Color(uiColor: .systemBackground))
                    .background(isSaved ? AnyShapeStyle(Theme.cardBackground) : AnyShapeStyle(Color.primary),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .sensoryFeedback(.selection, trigger: isSaved)
            .accessibilityAddTraits(isSaved ? .isSelected : [])

            if showsMapButton {
                IconAction(symbol: "map", label: String(localized: "Show on map")) {
                    dismiss()
                    app.showOnMap(place)
                }
            }
            ShareLink(item: ShareText.text(for: place)) {
                IconActionLabel(symbol: "square.and.arrow.up")
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(String(localized: "Share"))
            IconAction(symbol: "figure.walk", label: String(localized: "Walking directions")) {
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
            Text("Spotted something wrong? Every fact links to its sources.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
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

private struct IconAction: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconActionLabel(symbol: symbol)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct IconActionLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 54, height: 50)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
