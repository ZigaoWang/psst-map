import MapKit
import SwiftUI

/// A pitched, realistic-elevation map around the place, slowly circling unless Reduce Motion is on.
struct AerialMapView: View {
    let place: Place
    var animated = true
    @State private var position: MapCameraPosition = .automatic
    @State private var didInteract = false

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
            if MapFraming.shows3D(place) {
                Annotation(place.name, coordinate: place.mapCoordinate, anchor: .center) {
                    Circle()
                        .fill(place.spot.kind.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }
                .annotationTitles(.hidden)
            } else {
                Marker(place.name, systemImage: place.spot.kind.symbol, coordinate: place.mapCoordinate)
                    .tint(place.spot.kind.color)
            }
        }
        .mapStyle(MapFraming.shows3D(place)
                  ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
                  : .hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onAppear { position = .camera(camera(heading: MapFraming.heading(for: place))) }
        .task(id: place.id) {
            // Orbiting only makes sense in 3D; a flat map stays still and north-up.
            guard animated, MapFraming.shows3D(place) else { return }
            // A slow orbit gives the still map some life, like footage of the place.
            var heading = MapFraming.heading(for: place)
            try? await Task.sleep(for: .seconds(0.8))
            while !Task.isCancelled && !didInteract {
                heading += 40
                withAnimation(.linear(duration: 12)) {
                    position = .camera(camera(heading: heading))
                }
                try? await Task.sleep(for: .seconds(12))
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in didInteract = true })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "3D map of \(place.name)"))
    }

    private func camera(heading: Double) -> MapCamera {
        MapCamera(centerCoordinate: place.mapCoordinate, distance: MapFraming.distance(for: place),
                  heading: heading, pitch: MapFraming.pitch(for: place))
    }
}

/// The 3D map on its own screen, so it can use the whole display and every gesture.
struct AerialMapScreen: View {
    let place: Place
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            AerialMapView(place: place, animated: !reduceMotion)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(MapFraming.shows3D(place) ? "3D map. Drag to look around." : "Drag and pinch to explore.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .floatingSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 24, height: 24)
                    }
                    .floatingButtonStyle(circle: true)
                    .accessibilityLabel(String(localized: "Close"))
                    .accessibilityIdentifier("aerial.close")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
    }
}

/// Look Around, full screen and interactive, with a close button. Our own cover rather than MapKit's
/// `lookAroundViewer`, whose dark appearance stayed on the page underneath after it closed.
struct LookAroundScreen: View {
    let scene: MKLookAroundScene?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: true,
                          pointsOfInterest: .excludingAll, badgePosition: .bottomTrailing)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 20, height: 20)
                }
                .floatingButtonStyle(circle: true)
                .foregroundStyle(.primary)
                .padding(16)
                .accessibilityLabel(String(localized: "Close"))
            }
    }
}
