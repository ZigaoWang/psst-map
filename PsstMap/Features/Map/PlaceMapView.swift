import MapKit
import SwiftUI
import UIKit

/// MKMapView wrapper. UIKit is used here for clustering and for smooth handling of hundreds of pins.
struct PlaceMapView: UIViewRepresentable {
    let places: [Place]
    @Binding var selectedID: String?
    let focus: AppModel.MapFocus?
    let areaBounds: (String) -> Area.Bounds?
    let showsUserLocation: Bool
    /// Called with the WGS-84-ish center whenever the map settles, so the screen can name the area.
    let onRegionChange: (MKCoordinateRegion) -> Void
    /// Set by the screen to ask for a one-off camera move to a region (for "locate me").
    let regionRequest: RegionRequest?

    struct RegionRequest: Equatable {
        let region: MKCoordinateRegion
        let token = UUID()
        static func == (lhs: RegionRequest, rhs: RegionRequest) -> Bool { lhs.token == rhs.token }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let configuration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport, .park])
        map.preferredConfiguration = configuration
        map.showsCompass = true
        map.showsScale = true
        map.isPitchEnabled = true
        map.register(PlaceMarkerView.self, forAnnotationViewWithReuseIdentifier: PlaceMarkerView.reuseID)
        map.register(PlaceClusterView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        if let saved = MapRegionMemory.load() {
            map.setRegion(saved, animated: false)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.syncAnnotations(on: map, places: places)
        if map.showsUserLocation != showsUserLocation {
            map.showsUserLocation = showsUserLocation
        }
        if let focus, focus.token != coordinator.lastFocusToken {
            coordinator.lastFocusToken = focus.token
            coordinator.apply(focus, on: map)
        }
        if let regionRequest, regionRequest.token != coordinator.lastRegionToken {
            coordinator.lastRegionToken = regionRequest.token
            map.setRegion(regionRequest.region, animated: true)
        }
        coordinator.syncSelection(on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PlaceMapView
        var lastFocusToken: UUID?
        var lastRegionToken: UUID?
        private var annotationsByID: [String: PlaceAnnotation] = [:]
        private var isSyncingSelection = false
        private var didSetInitialRegion = false

        init(_ parent: PlaceMapView) {
            self.parent = parent
        }

        func syncAnnotations(on map: MKMapView, places: [Place]) {
            let newIDs = Set(places.map(\.id))
            guard newIDs != Set(annotationsByID.keys) else { return }
            let stale = annotationsByID.filter { !newIDs.contains($0.key) }
            map.removeAnnotations(Array(stale.values))
            stale.keys.forEach { annotationsByID[$0] = nil }
            let added = places.filter { annotationsByID[$0.id] == nil }.map(PlaceAnnotation.init)
            added.forEach { annotationsByID[$0.place.id] = $0 }
            map.addAnnotations(added)

            if !didSetInitialRegion, !places.isEmpty {
                didSetInitialRegion = true
                if MapRegionMemory.load() == nil {
                    showDefaultRegion(on: map, places: places)
                }
            }
        }

        /// First launch: frame the city with the most places.
        private func showDefaultRegion(on map: MKMapView, places: [Place]) {
            let byCity = Dictionary(grouping: places, by: \.city)
            guard let biggest = byCity.max(by: { $0.value.count < $1.value.count })?.value else { return }
            var rect = MKMapRect.null
            for place in biggest {
                let point = MKMapPoint(place.mapCoordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 120, right: 40),
                                  animated: false)
        }

        func syncSelection(on map: MKMapView) {
            let current = map.selectedAnnotations.compactMap { $0 as? PlaceAnnotation }.first?.place.id
            guard current != parent.selectedID else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            if let id = parent.selectedID, let annotation = annotationsByID[id] {
                map.selectAnnotation(annotation, animated: true)
            } else {
                map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) }
            }
        }

        func apply(_ focus: AppModel.MapFocus, on map: MKMapView) {
            switch focus.target {
            case .place(let id):
                guard let annotation = annotationsByID[id] else { return }
                let point = MKMapPoint(annotation.coordinate)
                let span = 700 * MKMapPointsPerMeterAtLatitude(annotation.coordinate.latitude)
                let rect = MKMapRect(x: point.x - span / 2, y: point.y - span / 2, width: span, height: span)
                // Keep the pin above the half-height sheet that opens with it.
                let bottom = map.bounds.height * 0.45
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 20, bottom: bottom, right: 20),
                                      animated: true)
                DispatchQueue.main.async { [weak self] in self?.parent.selectedID = id }
            case .area(let id):
                guard let bounds = parent.areaBounds(id) else { return }
                let sw = MKMapPoint(ChinaCoordinates.mapCoordinate(for: .init(latitude: bounds.south, longitude: bounds.west)))
                let ne = MKMapPoint(ChinaCoordinates.mapCoordinate(for: .init(latitude: bounds.north, longitude: bounds.east)))
                let rect = MKMapRect(x: min(sw.x, ne.x), y: min(sw.y, ne.y),
                                     width: abs(ne.x - sw.x), height: abs(ne.y - sw.y))
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 110, left: 24, bottom: 90, right: 24),
                                      animated: true)
                DispatchQueue.main.async { [weak self] in self?.parent.selectedID = nil }
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is PlaceAnnotation:
                return mapView.dequeueReusableAnnotationView(withIdentifier: PlaceMarkerView.reuseID, for: annotation)
            case is MKClusterAnnotation:
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation)
            default:
                return nil
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }
            guard !isSyncingSelection, let place = (annotation as? PlaceAnnotation)?.place else { return }
            if parent.selectedID != place.id {
                parent.selectedID = place.id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            guard !isSyncingSelection, let place = (annotation as? PlaceAnnotation)?.place else { return }
            // Deselection that is immediately followed by selecting another pin keeps the sheet open.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.selectedID == place.id,
                      mapView.selectedAnnotations.isEmpty else { return }
                self.parent.selectedID = nil
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            MapRegionMemory.save(mapView.region)
            parent.onRegionChange(mapView.region)
        }
    }
}

final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: Place
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(place: Place) {
        self.place = place
        self.coordinate = place.mapCoordinate
        self.title = place.name
    }
}

final class PlaceMarkerView: MKMarkerAnnotationView {
    static let reuseID = "place"

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "place"
        collisionMode = .circle
        titleVisibility = .adaptive
        subtitleVisibility = .hidden
        displayPriority = .defaultHigh
        animatesWhenAdded = false
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure() {
        guard let place = (annotation as? PlaceAnnotation)?.place else { return }
        let kind = place.spot.kind
        markerTintColor = kind.uiColor
        glyphTintColor = kind.onUIColor
        glyphImage = UIImage(systemName: kind.symbol)
        accessibilityLabel = place.name
        accessibilityValue = kind.label
        accessibilityHint = String(localized: "Shows what's surprising about this place")
    }
}

final class PlaceClusterView: MKMarkerAnnotationView {
    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        displayPriority = .required
        collisionMode = .circle
        titleVisibility = .hidden
        subtitleVisibility = .hidden
        markerTintColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xECEBE6) : UIColor(hex: 0x10182B) }
        glyphTintColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x10182B) : .white }
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count
        glyphText = count > 99 ? "99+" : "\(count)"
        accessibilityLabel = String(localized: "\(count) places")
        accessibilityHint = String(localized: "Zooms in to show them")
    }
}

/// Remembers where the map was, so it reopens where the person left it.
enum MapRegionMemory {
    private static let key = "map.lastRegion"

    static func save(_ region: MKCoordinateRegion) {
        UserDefaults.standard.set([region.center.latitude, region.center.longitude,
                                   region.span.latitudeDelta, region.span.longitudeDelta], forKey: key)
    }

    static func load() -> MKCoordinateRegion? {
        guard let values = UserDefaults.standard.array(forKey: key) as? [Double], values.count == 4 else { return nil }
        return MKCoordinateRegion(center: .init(latitude: values[0], longitude: values[1]),
                                  span: .init(latitudeDelta: values[2], longitudeDelta: values[3]))
    }
}
