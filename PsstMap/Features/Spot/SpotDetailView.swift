import MapKit
import SwiftUI

/// A place, presented as a sheet. Nearby places open inside it, with a back button.
struct SpotDetailView: View {
    let place: Place
    /// Hidden when the page was opened from the map already.
    var showsMapButton = true

    var body: some View {
        NavigationStack {
            PlacePage(place: place, showsMapButton: showsMapButton)
                .navigationDestination(for: Place.self) { next in
                    PlacePage(place: next, showsMapButton: showsMapButton)
                }
                .navigationDestination(for: Tag.self) { TagPlacesView(tag: $0) }
        }
    }
}

/// Everything about one place: a live map you can move around at the top, and the stories below it.
struct PlacePage: View {
    let place: Place
    let showsMapButton: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showsLookAround = false
    @State private var showsAerial = false

    private var mapHeight: CGFloat { typeSize.isAccessibilitySize ? 220 : 290 }

    var body: some View {
        // The map is a fixed header and the stories scroll below it, never underneath it, so the map
        // keeps every gesture and the text never slides behind its edge.
        VStack(spacing: 0) {
            mapHeader
                .frame(height: mapHeight)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    actions
                    stories
                    nearby
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
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
        .lookAroundViewer(isPresented: $showsLookAround, initialScene: lookAroundScene, allowsNavigation: true,
                          showsRoadLabels: true, pointsOfInterest: .excludingAll)
        .fullScreenCover(isPresented: $showsAerial) {
            AerialMapScreen(place: place)
        }
        .task(id: place.id) {
            let scene = await SpotVisuals.shared.lookAroundScene(for: place)
            withAnimation(.snappy) { lookAroundScene = scene }
        }
    }

    // MARK: Map

    private var mapHeader: some View {
        AerialMapView(place: place, animated: !reduceMotion)
            // Bottom right, so Apple's Maps logo and Legal link stay visible at the bottom left.
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    if lookAroundScene != nil {
                        Button {
                            showsLookAround = true
                        } label: {
                            Label("Look Around", systemImage: "binoculars.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .floatingButtonStyle()
                        .transition(.scale.combined(with: .opacity))
                    }
                    Button {
                        showsAerial = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 20, height: 20)
                    }
                    .floatingButtonStyle(circle: true)
                    .accessibilityLabel(String(localized: "Full-screen map"))
                }
                .foregroundStyle(.primary)
                .padding(12)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .overlay(alignment: .bottom) {
                Divider()
            }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.spot.kind.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(place.spot.kind.color)

            Text(place.name)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // The name on the signs, and the name in the reader's language when it's different again.
            let otherNames = [place.spot.localName, place.name(forLanguages: Locale.preferredLanguages)]
                .compactMap { $0 }
            if !otherNames.isEmpty {
                Text(otherNames.joined(separator: " · "))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(place.locationLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var actions: some View {
        let isSaved = app.saved.contains(place.id)
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { app.saved.toggle(place.id) }
                } label: {
                    Label(isSaved ? String(localized: "Saved") : String(localized: "Save"),
                          systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderedProminent)
                .tint(isSaved ? .secondary : .primary)
                .sensoryFeedback(.selection, trigger: isSaved)
                .accessibilityAddTraits(isSaved ? .isSelected : [])

                Button {
                    openInMaps()
                } label: {
                    Label(String(localized: "Walk here"), systemImage: "figure.walk")
                }
                .buttonStyle(.bordered)

                if showsMapButton {
                    Button {
                        dismiss()
                        app.showOnMap(place)
                    } label: {
                        Label(String(localized: "On map"), systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                }

                ShareLink(item: ShareText.text(for: place)) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .tint(.primary)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: Stories

    private var stories: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(Array(place.spot.facts.enumerated()), id: \.element.id) { index, fact in
                if index > 0 { Divider() }
                FactCard(fact: fact)
            }
        }
    }

    // MARK: Nearby

    private var neighbors: [Place] {
        Array(Nearby.places(around: place, in: app.visiblePlaces, limit: 7).dropFirst())
    }

    @ViewBuilder
    private var nearby: some View {
        if !neighbors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nearby")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(neighbors) { neighbor in
                            NavigationLink(value: neighbor) {
                                NearbyCard(place: neighbor, from: place)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = place.spot.coordinateSource.url {
                Link(destination: url) {
                    Text(place.spot.coordinateSource.isOpenStreetMap
                         ? "Location © OpenStreetMap contributors"
                         : "Location from Wikidata")
                        .underline()
                }
                if place.spot.coordinateSource.isOpenStreetMap,
                   let license = URL(string: "https://www.openstreetmap.org/copyright") {
                    Link("Open Database License", destination: license)
                }
            }
            Text("Spotted something wrong? Every story links to its sources.")
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

/// A small picture card for a place near the one being read.
private struct NearbyCard: View {
    let place: Place
    let from: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaceThumbnail(place: place)
                .frame(width: 150, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(distance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var distance: String {
        let meters = place.location.distance(from: from.location)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = meters < 1_000 ? 0 : 1
        let rounded = meters < 1_000 ? (meters / 10).rounded() * 10 : meters
        return String(localized: "\(formatter.string(from: Measurement(value: rounded, unit: UnitLength.meters))) away")
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
