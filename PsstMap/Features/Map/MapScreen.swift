import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?
    @State private var showsSearch = false
    @State private var showsKey = false
    @State private var visibleAreaName: String?
    @State private var regionRequest: PlaceMapView.RegionRequest?
    @State private var isLocating = false
    @State private var locationProblem: LocationProblem?
    @State private var detailPlace: Place?

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
            areaBounds: { app.catalog.area(id: $0)?.bounds },
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
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.18), value: selectedID == nil)
        .sheet(item: $detailPlace) { place in
            SpotDetailView(place: place, showsMapButton: false)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsSearch) {
            SearchSheet(onPlace: { place in
                showsSearch = false
                app.showOnMap(place)
            }, onArea: { areaID in
                showsSearch = false
                app.mapFocus = AppModel.MapFocus(target: .area(areaID))
            })
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
        .sensoryFeedback(.selection, trigger: app.shownCategories)
    }

    private func updateVisibleArea(_ region: MKCoordinateRegion) {
        // Only name an area when zoomed in far enough for it to mean something.
        guard region.span.latitudeDelta < 0.25 else {
            visibleAreaName = nearestCity(to: region.center)
            return
        }
        let center = region.center
        let containing = app.catalog.areas.first { area in
            let sw = MapDatum.shared.mapCoordinate(for: .init(latitude: area.bounds.south, longitude: area.bounds.west))
            let ne = MapDatum.shared.mapCoordinate(for: .init(latitude: area.bounds.north, longitude: area.bounds.east))
            return (sw.latitude...ne.latitude).contains(center.latitude)
                && (sw.longitude...ne.longitude).contains(center.longitude)
        }
        visibleAreaName = containing?.name ?? nearestCity(to: center)
    }

    private func nearestCity(to center: CLLocationCoordinate2D) -> String? {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let nearest = app.catalog.areas.min { a, b in
            here.distance(from: CLLocation(latitude: a.bounds.center.latitude, longitude: a.bounds.center.longitude))
                < here.distance(from: CLLocation(latitude: b.bounds.center.latitude, longitude: b.bounds.center.longitude))
        }
        guard let nearest else { return nil }
        let distance = here.distance(from: CLLocation(latitude: nearest.bounds.center.latitude,
                                                      longitude: nearest.bounds.center.longitude))
        return distance < 60_000 ? nearest.city : nil
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
