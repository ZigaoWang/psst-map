import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?
    @State private var showsAreas = false
    @State private var showsKey = false
    @State private var visibleAreaName: String?
    @State private var regionRequest: PlaceMapView.RegionRequest?
    @State private var isLocating = false
    @State private var locationProblem: LocationProblem?
    @State private var detailPlace: Place?
    /// The places in the card carousel. Rebuilt around a pin when it is tapped on the map,
    /// but left alone while the person swipes through it.
    @State private var carousel: [Place] = []

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
            if !carousel.isEmpty {
                PlaceCarousel(places: carousel, selectedID: $selectedID,
                              onOpen: { detailPlace = $0 },
                              onClose: { selectedID = nil },
                              onReveal: { app.mapFocus = AppModel.MapFocus(target: .reveal($0)) })
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.18), value: selectedID == nil)
        .sheet(item: $detailPlace) { place in
            SpotDetailView(place: place, showsMapButton: false)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAreas) {
            AreasSheet { areaID in
                showsAreas = false
                app.mapFocus = AppModel.MapFocus(target: .area(areaID))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsKey) {
            MapKeySheet()
                .presentationDetents([.medium, .large])
        }
        #if DEBUG
        .onAppear {
            switch UserDefaults.standard.string(forKey: "debug.sheet") {
            case "areas": showsAreas = true
            case "key": showsKey = true
            default: break
            }
        }
        #endif
        .onChange(of: selectedID) { _, id in
            guard let id else {
                carousel = []
                return
            }
            if !carousel.contains(where: { $0.id == id }), let place = app.catalog.place(id: id) {
                carousel = PlaceCarousel.neighborhood(of: place, in: app.visiblePlaces)
            }
        }
        .onChange(of: app.hiddenKinds) {
            if let place = selectedPlace, app.hiddenKinds.contains(place.spot.kind) { selectedID = nil }
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
                      primaryButton: .default(Text("Choose an area")) { showsAreas = true },
                      secondaryButton: .cancel(Text("Show me anyway")) { centerOnUser() })
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showsAreas = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .imageScale(.medium)
                        Text(visibleAreaName ?? String(localized: "Choose an area"))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 28)
                }
                .floatingButtonStyle()
                .accessibilityLabel(visibleAreaName.map { String(localized: "Area: \($0)") } ?? String(localized: "Choose an area"))
                .accessibilityHint(String(localized: "Shows all areas"))

                if app.isFiltering {
                    Button {
                        withAnimation(.snappy) { app.showAllKinds() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease")
                            Text("\(Spot.Kind.allCases.count - app.hiddenKinds.count) of \(Spot.Kind.allCases.count) kinds")
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    }
                    .floatingButtonStyle()
                    .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
                    .accessibilityLabel(String(localized: "Filter on"))
                    .accessibilityHint(String(localized: "Shows every kind of place again"))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
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
                Button { showsKey = true } label: {
                    Image(systemName: app.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "list.bullet.rectangle")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 24)
                }
                .floatingButtonStyle(circle: true)
                .accessibilityLabel(String(localized: "Map key"))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
