import MapKit
import SwiftUI

/// One full-screen page of the feed: the picture, the place, and its best secret. Nothing else.
struct FeedCard: View {
    let place: Place
    let size: CGSize
    let isActive: Bool
    let onOpen: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.safeAreaInsets) private var safeArea
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showsLookAround = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FeedPicture(place: place, size: pictureSize, isActive: isActive)
                .frame(width: size.width, height: size.height)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .clear, location: 0.2),
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.7), location: 0.62),
                .init(color: .black.opacity(0.88), location: 0.8),
                .init(color: .black.opacity(0.92), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 20) {
                text
                actions
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 20)
            .padding(.bottom, bottomPadding)
        }
        .frame(width: size.width, height: size.height)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(String(localized: "Double-tap for the full story and sources"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("feed.card")
        .accessibilityAction(named: app.saved.contains(place.id) ? String(localized: "Remove from saved") : String(localized: "Save")) {
            app.saved.toggle(place.id)
        }
        .accessibilityAction(named: String(localized: "Show on map")) { app.showOnMap(place) }
        .lookAround(isPresented: $showsLookAround, scene: lookAroundScene)
        .task(id: isActive) {
            // Only the card on screen asks Apple for Look Around, so scrolling stays light.
            guard isActive, lookAroundScene == nil else { return }
            let scene = await SpotVisuals.shared.lookAroundScene(for: place)
            withAnimation(.snappy) { lookAroundScene = scene }
        }
    }

    /// Pictures are made at the card's full size and shared with the map card and place page.
    private var pictureSize: CGSize { Self.pictureSize(for: size) }

    static func pictureSize(for cardSize: CGSize) -> CGSize {
        CGSize(width: cardSize.width.rounded(), height: cardSize.height.rounded())
    }

    private var bottomPadding: CGFloat {
        // Clear the floating tab bar, which sits at the top on iPad.
        safeArea.bottom + (horizontalSizeClass == .regular ? 32 : 60)
    }

    private var fact: Fact { app.leadFact(for: place) }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(place.spot.kind.color)
                    .frame(width: 8, height: 8)
                Text(place.locationLine)
                if fact.status != .fact {
                    Text("· \(fact.status.label)")
                        .foregroundStyle(fact.status == .legend ? Color(white: 0.85) : .white.opacity(0.7))
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)

            Text(place.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text.story(fact.short)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(3)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 6)

            HStack(spacing: 4) {
                Text("Read more")
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 2)

            if let photo = place.spot.currentPhotos.first {
                PhotoCredit(photo: photo, color: .white.opacity(0.55))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
    }

    private var actions: some View {
        let isSaved = app.saved.contains(place.id)
        return VStack(spacing: 22) {
            if lookAroundScene != nil {
                IconButton(symbol: "binoculars", label: String(localized: "Look Around")) {
                    showsLookAround = true
                }
                .transition(.scale.combined(with: .opacity))
            }
            IconButton(symbol: isSaved ? "bookmark.fill" : "bookmark",
                       label: isSaved ? String(localized: "Remove from saved") : String(localized: "Save")) {
                app.saved.toggle(place.id)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isSaved)
            IconButton(symbol: "map", label: String(localized: "Show on map")) {
                app.showOnMap(place)
            }
            ShareLink(item: ShareText.text(for: place)) {
                IconLabel(symbol: "square.and.arrow.up")
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(String(localized: "Share"))
        }
    }

    private var accessibilityText: String {
        var parts = [place.name, place.locationLine]
        if fact.status == .legend { parts.append(String(localized: "Legend, not a proven fact")) }
        if fact.status == .disputed { parts.append(String(localized: "Disputed")) }
        parts.append(fact.short)
        return parts.joined(separator: ". ")
    }
}

private struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconLabel(symbol: symbol)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct IconLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            .contentShape(Rectangle())
            .contentTransition(.symbolEffect(.replace))
    }
}

/// The card's picture, with a slow push-in while it is on screen.
struct FeedPicture: View {
    let place: Place
    let size: CGSize
    let isActive: Bool

    @State private var picture: SpotVisuals.Picture?
    @State private var didFail = false
    @State private var zoomed = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let photo = place.spot.currentPhotos.first {
                PlacePhotoImage(photo: photo, size: .full, placeholder: place.spot.kind.color.opacity(0.35))
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(zoomed ? 1.09 : 1.0, anchor: .center)
            } else if let picture {
                Image(uiImage: picture.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(zoomed ? 1.09 : 1.0, anchor: .center)
                    .id(picture.image)
                    .transition(.opacity)
            } else {
                VisualPlaceholder(kind: place.spot.kind, isLoading: !didFail,
                                  message: didFail ? String(localized: "No picture right now") : nil)
            }
        }
        .task(id: place.id) {
            picture = nil
            didFail = false
            guard place.spot.currentPhotos.isEmpty else { return }
            let result = await SpotVisuals.shared.picture(for: place, size: size, scale: min(displayScale, 2),
                                                          dark: true) { update in
                withAnimation(.easeOut(duration: 0.4)) { picture = update }
            }
            if Task.isCancelled { return }
            didFail = result == nil
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard !reduceMotion else { return }
            if active {
                withAnimation(.linear(duration: 14)) { zoomed = true }
            } else {
                zoomed = false
            }
        }
    }
}

extension EnvironmentValues {
    /// The window's safe area, for layouts that ignore it but still need to clear system bars.
    @Entry var safeAreaInsets = EdgeInsets()
}
