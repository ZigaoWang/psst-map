import MapKit
import SwiftUI

/// The interactive picture at the top of a place: Look Around where Apple has it, a 3D map otherwise.
struct SpotVisualView: View {
    let place: Place

    enum Mode: Hashable {
        case street, aerial
    }

    @State private var scene: MKLookAroundScene?
    @State private var isResolving = true
    @State private var mode: Mode = .street
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            if scene != nil {
                modePicker
                    .padding(10)
            }
        }
        .task(id: place.id) {
            isResolving = true
            scene = nil
            mode = place.spot.size == .large ? .aerial : .street
            scene = await SpotVisuals.shared.lookAroundScene(for: place)
            isResolving = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if isResolving {
            VisualPlaceholder(kind: place.spot.kind, isLoading: true)
        } else if let scene, mode == .street {
            LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: false,
                              pointsOfInterest: .excludingAll, badgePosition: .bottomTrailing)
                .accessibilityLabel(String(localized: "Street-level view of \(place.name)"))
        } else {
            AerialMapView(place: place, animated: !reduceMotion)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            modeButton(.street, title: String(localized: "Street"), symbol: "binoculars.fill")
            modeButton(.aerial, title: String(localized: "3D"), symbol: "view.3d")
        }
        .padding(3)
        .floatingSurface(in: Capsule())
    }

    private func modeButton(_ value: Mode, title: String, symbol: String) -> some View {
        Button {
            withAnimation(.snappy) { mode = value }
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(mode == value ? Color.primary.opacity(0.14) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

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
