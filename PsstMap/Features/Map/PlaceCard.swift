import CoreLocation
import SwiftUI

/// The card for the selected pin: the place's picture with its name and best story. Tap it for the
/// full page; swipe it down or tap the close button to put it away. Tapping another pin swaps it.
struct PlaceCard: View {
    let place: Place
    let onOpen: () -> Void
    let onClose: () -> Void

    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack {
            PlaceMiniCard(place: place, onClose: onClose)
                .id(place.id)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(.snappy(duration: 0.25), value: place.id)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .offset(y: max(drag, 0))
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 60 || value.predictedEndTranslation.height > 160 {
                        onClose()
                    } else if value.translation.height < -40 {
                        onOpen()
                    }
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { drag = 0 }
                }
        )
        .sensoryFeedback(.selection, trigger: place.id)
    }
}

enum Nearby {
    /// The place first, then its nearest neighbors within 3 km among the places given.
    static func places(around place: Place, in places: [Place], limit: Int = 12) -> [Place] {
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
            Text.story(app.leadFact(for: place).short)
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
        .accessibilityHint(String(localized: "Opens the full story"))
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
                if let photo = place.spot.currentPhotos.first {
                    PlacePhotoImage(photo: photo, placeholder: .clear)
                } else if let picture {
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
            guard place.spot.currentPhotos.isEmpty else { return }
            let size = FeedCard.pictureSize(for: UIScreen.main.bounds.size)
            await SpotVisuals.shared.picture(for: place, size: size, scale: 2, dark: true) { update in
                withAnimation(.easeOut(duration: 0.25)) { picture = update }
            }
        }
    }
}
