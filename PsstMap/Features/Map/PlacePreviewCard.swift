import SwiftUI

/// The small card that appears when a pin is tapped. Tap it or swipe it up for the full story;
/// swipe it down or tap the map to put it away.
struct PlacePreviewCard: View {
    let place: Place
    let onOpen: () -> Void
    let onClose: () -> Void

    @State private var drag: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PlaceThumbnail(place: place)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    KindBadge(kind: place.spot.kind, compact: true)
                    Text(place.areaName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(place.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(place.leadFact.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(storyLabel)
                    Image(systemName: "chevron.up")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityLabel(String(localized: "Close"))
        }
        .padding(12)
        .padding(.trailing, -6)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .offset(y: drag > 0 ? drag : drag * 0.25)
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    let predicted = value.predictedEndTranslation.height
                    if value.translation.height < -40 || predicted < -120 {
                        onOpen()
                    } else if value.translation.height > 60 || predicted > 160 {
                        onClose()
                    }
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) { drag = 0 }
                }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: place.id)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: String(localized: "Read the story"), onOpen)
    }

    private var thumbnailSize: CGFloat { typeSize.isAccessibilitySize ? 72 : 92 }

    private var storyLabel: String {
        let count = place.spot.facts.count
        return count == 1 ? String(localized: "Read the story") : String(localized: "Read \(count) stories")
    }
}

/// A small square picture of a place, sharing the feed's picture cache.
struct PlaceThumbnail: View {
    let place: Place
    @State private var picture: SpotVisuals.Picture?

    var body: some View {
        ZStack {
            place.spot.kind.color
            Image(systemName: place.spot.kind.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(place.spot.kind.onColor.opacity(0.9))
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
