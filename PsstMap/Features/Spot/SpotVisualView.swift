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
            modeButton(.aerial, title: String(localized: "3D"), symbol: "cube")
        }
        .padding(3)
        .floatingSurface(in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
