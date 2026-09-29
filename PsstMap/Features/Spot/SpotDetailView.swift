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
    @State private var scrolled: CGFloat = 0
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showsLookAround = false
    @State private var showsAerial = false

    private var fullMapHeight: CGFloat { typeSize.isAccessibilitySize ? 240 : 320 }
    private let collapsedMapHeight: CGFloat = 150

    /// The map gives up height as the text scrolls up, down to a strip that still shows where you are.
    private var mapHeight: CGFloat {
        max(collapsedMapHeight, fullMapHeight - max(scrolled, 0))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollOffsetKey.self,
                                               value: -proxy.frame(in: .named("page")).minY)
                    }
                    .frame(height: fullMapHeight)

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
            .coordinateSpace(name: "page")
            .onPreferenceChange(ScrollOffsetKey.self) { scrolled = $0 }

            mapHeader
                .frame(height: mapHeight)
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
                .opacity(mapHeight > collapsedMapHeight + 40 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: mapHeight > collapsedMapHeight + 40)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(scrolled > 4 ? 0.15 : 0), radius: 10, y: 4)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(place.spot.kind.color)
                    .frame(width: 9, height: 9)
                Text("\(place.spot.kind.label) · \(place.areaName)")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)

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
        return HStack(spacing: 8) {
            PageAction(title: isSaved ? String(localized: "Saved") : String(localized: "Save"),
                       symbol: isSaved ? "bookmark.fill" : "bookmark", isOn: isSaved) {
                withAnimation(.snappy) { app.saved.toggle(place.id) }
            }
            .sensoryFeedback(.selection, trigger: isSaved)

            PageAction(title: String(localized: "Walk here"), symbol: "figure.walk") {
                openInMaps()
            }

            if showsMapButton {
                PageAction(title: String(localized: "On map"), symbol: "map") {
                    dismiss()
                    app.showOnMap(place)
                }
            }

            ShareLink(item: ShareText.text(for: place)) {
                PageActionLabel(title: String(localized: "Share"), symbol: "square.and.arrow.up", isOn: false)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    // MARK: Stories

    private var stories: some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(Array(place.spot.facts.enumerated()), id: \.element.id) { index, fact in
                FactCard(fact: fact, number: index + 1)
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
                    HStack(spacing: 12) {
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
                    Text(place.spot.coordinateSource.isWikidata
                         ? "Location from Wikidata"
                         : "Location from OpenStreetMap contributors")
                        .underline()
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

nonisolated private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct PageAction: View {
    let title: String
    let symbol: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PageActionLabel(title: title, symbol: symbol, isOn: isOn)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct PageActionLabel: View {
    let title: String
    let symbol: String
    let isOn: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isOn ? Color(uiColor: .systemBackground) : .primary)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(isOn ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Theme.cardBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
