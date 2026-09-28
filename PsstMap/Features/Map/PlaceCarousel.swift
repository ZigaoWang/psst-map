import CoreLocation
import SwiftUI

/// Picture cards for the selected place and its neighbors. Swipe sideways to move between nearby
/// places, tap a card for the full story, swipe down or tap the close button to put them away.
struct PlaceCarousel: View {
    let places: [Place]
    @Binding var selectedID: String?
    let onOpen: (Place) -> Void
    let onClose: () -> Void
    let onReveal: (String) -> Void

    @State private var scrolledID: String?
    @State private var drag: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(places) { place in
                    PlaceMiniCard(place: place, onClose: onClose)
                        .containerRelativeFrame(.horizontal) { width, _ in min(width - 40, 520) }
                        .onTapGesture { onOpen(place) }
                        .id(place.id)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: 176)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledID)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .offset(y: max(drag, 0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    drag = value.translation.height
                }
                .onEnded { value in
                    if drag > 70 || value.predictedEndTranslation.height > 180 {
                        onClose()
                    }
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { drag = 0 }
                }
        )
        .onAppear { scrolledID = selectedID }
        .onChange(of: selectedID) { _, id in
            guard let id, id != scrolledID else { return }
            withAnimation(.snappy) { scrolledID = id }
        }
        .onChange(of: scrolledID) { _, id in
            guard let id, id != selectedID else { return }
            selectedID = id
            onReveal(id)
        }
        .sensoryFeedback(.selection, trigger: scrolledID)
    }

    /// The selected place first, then its nearest neighbors among the places on the map.
    static func neighborhood(of place: Place, in places: [Place], limit: Int = 12) -> [Place] {
        let here = place.location
        let others = places
            .filter { $0.id != place.id }
            .map { ($0, $0.location.distance(from: here)) }
            .filter { $0.1 < 3_000 }
            .sorted { $0.1 < $1.1 }
            .prefix(limit - 1)
            .map(\.0)
        return [place] + others
    }
}

/// One card: the place's picture with its name and first secret over it.
private struct PlaceMiniCard: View {
    let place: Place
    let onClose: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(place.spot.kind.color).frame(width: 8, height: 8)
                Text(place.spot.kind.label)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.8))
            Text(place.name)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(app.leadFact(for: place).short)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background {
            PlaceThumbnail(place: place)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: .black.opacity(0.7), location: 0.65),
                        .init(color: .black.opacity(0.85), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .frame(height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.4), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(String(localized: "Close"))
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Opens the full story. Swipe sideways for places nearby."))
        .accessibilityAddTraits(.isButton)
    }
}

struct PlaceThumbnail: View {
    let place: Place
    @State private var picture: SpotVisuals.Picture?

    var body: some View {
        // The rectangle sets the size; the picture fills it without being able to change it.
        Rectangle()
            .fill(place.spot.kind.color)
            .overlay {
                Image(systemName: place.spot.kind.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(place.spot.kind.onColor.opacity(0.9))
            }
            .overlay {
                if let picture {
                    Image(uiImage: picture.image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
        .accessibilityHidden(true)
        .task(id: place.id) {
            picture = nil
            let size = FeedCard.pictureSize(for: UIScreen.main.bounds.size)
            await SpotVisuals.shared.picture(for: place, size: size, scale: 2, dark: true) { update in
                withAnimation(.easeOut(duration: 0.25)) { picture = update }
            }
        }
    }
}
