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
            Annotation(place.name, coordinate: place.mapCoordinate, anchor: .center) {
                Circle()
                    .fill(place.spot.kind.color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(radius: 3)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onAppear { position = .camera(camera(heading: MapFraming.heading(for: place))) }
        .task(id: place.id) {
            guard animated else { return }
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
        MapCamera(centerCoordinate: place.mapCoordinate, distance: MapFraming.distance(for: place) * 1.4,
                  heading: heading, pitch: 60)
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
                        Text("3D map. Drag to look around.")
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
