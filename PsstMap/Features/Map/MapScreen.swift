import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?
    @State private var showsSearch = false
    @State private var openTag: Tag?
    @State private var showsKey = false
    @State private var visibleAreaName: String?
    @State private var regionRequest: PlaceMapView.RegionRequest?
    @State private var isLocating = false
    @State private var locationProblem: LocationProblem?
    @State private var detailPlace: Place?
    @Namespace private var zoom

    enum LocationProblem: Identifiable {
        case denied, unavailable, nothingNearby
        var id: Self { self }
    }

    private var selectedPlace: Place? {
        selectedID.flatMap { app.catalog.place(id: $0) }
    }

    var body: some View {
        PlaceMapView(
            places: app.visiblePlaces,
            selectedID: $selectedID,
            focus: app.mapFocus,
            showsUserLocation: app.location.isAuthorized,
            onRegionChange: updateVisibleArea,
            regionRequest: regionRequest,
            datumVersion: MapDatum.shared.version
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) {
            if let place = selectedPlace {
                PlaceCard(place: place, onOpen: { detailPlace = place }, onClose: { selectedID = nil })
                    .placeZoomSource(place.id, in: zoom)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.18), value: selectedID == nil)
        .placePresentation($detailPlace, namespace: zoom, showsMapButton: false)
        .sheet(isPresented: $showsSearch) {
            SearchSheet(onPlace: { place in
                showsSearch = false
                app.showOnMap(place)
            }, onRegion: { bounds in
                showsSearch = false
                app.mapFocus = AppModel.MapFocus(target: .bounds(bounds))
            }, onTag: { tag in
                showsSearch = false
                openTag = tag
            })
        }
        .sheet(item: $openTag) { tag in
            TagSheet(tag: tag)
        }
        .sheet(isPresented: $showsKey) {
            FilterSheet()
                .presentationDetents([.medium, .large])
        }
        #if DEBUG
        .onAppear {
            switch UserDefaults.standard.string(forKey: "debug.sheet") {
            case "search": showsSearch = true
            case "key": showsKey = true
            default: break
            }
        }
        #endif
        .onChange(of: app.visiblePlaces.count) {
            if let place = selectedPlace, !app.isVisible(place) { selectedID = nil }
        }
        #if DEBUG
        .onChange(of: selectedID) { _, new in
            if let new, UserDefaults.standard.bool(forKey: "debug.detail") { detailPlace = app.catalog.place(id: new) }
        }
        #endif
        .alert(item: $locationProblem) { problem in
            switch problem {
            case .denied:
                Alert(title: Text("Location is off for Psst"),
                      message: Text("Turn it on in Settings to see the places around you."),
                      primaryButton: .default(Text("Open Settings")) {
                          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                      },
                      secondaryButton: .cancel(Text("Not now")))
            case .unavailable:
                Alert(title: Text("Can't find your location"),
                      message: Text("Check that Location Services are on, then try again."),
                      dismissButton: .default(Text("OK")))
            case .nothingNearby:
                Alert(title: Text("Nothing near you yet"),
                      message: Text("Psst doesn't cover where you are right now. Pick an area to explore instead."),
                      primaryButton: .default(Text("Choose an area")) { showsSearch = true },
                      secondaryButton: .cancel(Text("Show me anyway")) { centerOnUser() })
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showsSearch = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        if let visibleAreaName {
                            Text(visibleAreaName)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .floatingButtonStyle()
                .accessibilityLabel(String(localized: "Search places"))
                .accessibilityValue(visibleAreaName ?? "")
                .accessibilityHint(String(localized: "Find a place, or browse areas"))

                Button { showsKey = true } label: {
                    Image(systemName: app.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 24)
                }
                .floatingButtonStyle(circle: true)
                .accessibilityLabel(String(localized: "Filter"))

                Button(action: locate) {
                    Group {
                        if isLocating {
                            ProgressView()
                        } else {
                            Image(systemName: app.location.isAuthorized ? "location.fill" : "location")
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .floatingButtonStyle(circle: true)
                .accessibilityLabel(String(localized: "Show my location"))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)

            storyChips
        }
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// One tap to see only one kind of story. Tapping more adds them; "All" clears.
    private var storyChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if !app.shownKinds.isEmpty {
                    Button {
                        withAnimation(.snappy) { app.shownKinds = [] }
                    } label: {
                        HStack(spacing: 5) {
                            Text(app.shownKinds.count == 1 ? app.shownKinds.first!.label
                                 : String(localized: "\(app.shownKinds.count) kinds"))
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .chipButtonStyle(isOn: true, color: .primary.opacity(0.8))
                    .accessibilityHint(String(localized: "Shows every kind of place again"))
                }
                Button {
                    withAnimation(.snappy) { app.shownCategories = [] }
                } label: {
                    Text("All stories")
                        .font(.subheadline.weight(.semibold))
                }
                .chipButtonStyle(isOn: app.shownCategories.isEmpty, color: Theme.ink)
                .accessibilityAddTraits(app.shownCategories.isEmpty ? .isSelected : [])

                ForEach(Fact.Category.displayOrder, id: \.self) { category in
                    let isOn = app.shownCategories.contains(category)
                    Button {
                        withAnimation(.snappy) { app.toggle(category) }
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                            .font(.subheadline.weight(.semibold))
                    }
                    .chipButtonStyle(isOn: isOn, color: category.color)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .modifier(NoScrollEdgeEffect())
        // Without this the row clips its buttons' shadows into a hard-edged band across the map.
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: app.shownCategories)
    }

    private func updateVisibleArea(_ region: MKCoordinateRegion) {
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let span = region.span
        let visible = app.visiblePlaces.filter { place in
            abs(place.coordinate.latitude - region.center.latitude) <= span.latitudeDelta / 2
                && abs(place.coordinate.longitude - region.center.longitude) <= span.longitudeDelta / 2
        }
        // Zoomed in: the neighborhood of the place nearest the middle. Zoomed out: the city.
        if span.latitudeDelta < 0.06,
           let nearest = visible.min(by: { $0.location.distance(from: center) < $1.location.distance(from: center) }) {
            visibleAreaName = nearest.neighborhoodName ?? nearest.city
        } else {
            visibleAreaName = nearestCity(to: center)?.displayName
        }
        // A city-sized view with no places at all (whatever the filters): tell us, anonymously, which
        // coarse cell someone looked at. Never sent while the person's own location is in view.
        if app.loadState == .loaded {
            let hasPlaces = app.catalog.places.contains { place in
                abs(place.coordinate.latitude - region.center.latitude) <= span.latitudeDelta / 2
                    && abs(place.coordinate.longitude - region.center.longitude) <= span.longitudeDelta / 2
            }
            if let cell = DemandSignal.cell(center: region.center, span: span, hasPlaces: hasPlaces,
                                            userLocation: app.location.location?.coordinate) {
                DemandSignal.send(cell: cell)
            }
        }
    }

    private func nearestCity(to center: CLLocation) -> City? {
        app.catalog.cities
            .map { ($0, center.distance(from: CLLocation(latitude: $0.bounds.center.latitude,
                                                         longitude: $0.bounds.center.longitude))) }
            .filter { $0.1 < 60_000 }
            .min { $0.1 < $1.1 }?.0
    }

    private func locate() {
        if app.location.isDenied {
            locationProblem = .denied
            return
        }
        isLocating = true
        Task {
            let location = await app.location.currentLocation()
            isLocating = false
            guard let location else {
                locationProblem = app.location.isDenied ? .denied : .unavailable
                return
            }
            if app.catalog.places(near: location, within: 25_000).isEmpty {
                locationProblem = .nothingNearby
            } else {
                centerOn(location)
            }
        }
    }

    private func centerOnUser() {
        if let location = app.location.location { centerOn(location) }
    }

    private func centerOn(_ location: CLLocation) {
        let center = MapDatum.shared.mapCoordinate(for: location.coordinate)
        regionRequest = .init(region: MKCoordinateRegion(center: center, latitudinalMeters: 1_400, longitudinalMeters: 1_400))
    }
}

/// Floating rows over the map shouldn't get iOS 26's scroll edge fade, which draws a band across the map.
private struct NoScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}
