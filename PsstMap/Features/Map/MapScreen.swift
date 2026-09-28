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

    enum LocationProblem: Identifiable {
        case denied, unavailable, nothingNearby
        var id: Self { self }
    }

    private var selectedPlace: Binding<Place?> {
        Binding(
            get: { selectedID.flatMap { app.catalog.place(id: $0) } },
            set: { selectedID = $0?.id }
        )
    }

    var body: some View {
        PlaceMapView(
            places: app.catalog.places,
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
        .sheet(item: selectedPlace) { place in
            SpotDetailView(place: place, showsMapButton: false, onClose: { selectedID = nil })
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.scrolls)
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
            Button {
                showsAreas = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .imageScale(.medium)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(visibleAreaName ?? String(localized: "Choose an area"))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .floatingSurface(in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(visibleAreaName.map { String(localized: "Area: \($0)") } ?? String(localized: "Choose an area"))
            .accessibilityHint(String(localized: "Shows all areas"))

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Button(action: locate) {
                    Group {
                        if isLocating {
                            ProgressView()
                        } else {
                            Image(systemName: app.location.isAuthorized ? "location.fill" : "location")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Show my location"))
                Divider().frame(width: 28)
                Button { showsKey = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Map key"))
            }
            .buttonStyle(.plain)
            .font(.body.weight(.medium))
            .floatingSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
