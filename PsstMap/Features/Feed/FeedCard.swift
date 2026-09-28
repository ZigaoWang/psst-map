import SwiftUI

/// One full-screen page of the feed.
struct FeedCard: View {
    let place: Place
    let size: CGSize
    let isActive: Bool
    let onOpen: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.safeAreaInsets) private var safeArea
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            VStack(spacing: 0) {
                FeedPicture(place: place, size: pictureSize, isActive: isActive)
                    .frame(width: pictureSize.width, height: pictureSize.height)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        // Fade the picture into the black text area.
                        LinearGradient(colors: [.clear, .black.opacity(0.6), .black],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: pictureSize.height * (typeSize.isAccessibilitySize ? 0.8 : 0.4))
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 140)
                    }
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)

            content
                .frame(maxWidth: 760)
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
        .accessibilityAction(named: app.saved.contains(place.id) ? String(localized: "Remove from saved") : String(localized: "Save")) {
            app.saved.toggle(place.id)
        }
        .accessibilityAction(named: String(localized: "Show on map")) { app.showOnMap(place) }
    }

    /// The picture takes the top of the card; the text sits below it on black.
    private var pictureSize: CGSize { Self.pictureSize(for: size) }

    static func pictureSize(for cardSize: CGSize) -> CGSize {
        CGSize(width: cardSize.width, height: (cardSize.height * 0.64).rounded())
    }

    private var bottomPadding: CGFloat {
        // Clear the floating tab bar, which sits at the top on iPad.
        safeArea.bottom + (horizontalSizeClass == .regular ? 40 : 64)
    }

    private var fact: Fact { place.leadFact }

    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                text
                rail(axis: .horizontal)
            }
        } else {
            HStack(alignment: .bottom, spacing: 16) {
                text
                rail(axis: .vertical)
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KindBadge(kind: place.spot.kind, compact: typeSize.isAccessibilitySize)
                Text(place.areaName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 3)
                    .minimumScaleFactor(0.8)
                if let local = place.spot.localName {
                    Text(local)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            if fact.status != .fact {
                StatusBadge(status: fact.status)
            }
            Text(fact.short)
                .font(.title3)
                .foregroundStyle(.white)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : nil)
                .fixedSize(horizontal: false, vertical: !typeSize.isAccessibilitySize)
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(moreLabel)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }

    private var moreLabel: String {
        let others = place.spot.facts.count - 1
        if others <= 0 { return String(localized: "Read the story") }
        return others == 1
            ? String(localized: "Read the story and 1 more")
            : String(localized: "Read the story and \(others) more")
    }

    @ViewBuilder
    private func rail(axis: Axis) -> some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 22))
        let isSaved = app.saved.contains(place.id)
        layout {
            RailButton(symbol: isSaved ? "bookmark.fill" : "bookmark",
                       title: isSaved ? String(localized: "Saved") : String(localized: "Save")) {
                app.saved.toggle(place.id)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isSaved)
            RailButton(symbol: "map", title: String(localized: "Map")) {
                app.showOnMap(place)
            }
            ShareLink(item: ShareText.text(for: place)) {
                RailLabel(symbol: "square.and.arrow.up", title: String(localized: "Share"))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, axis == .vertical ? 48 : 0)
    }

    private var accessibilityText: String {
        var parts = [place.name, place.spot.kind.label, place.areaName]
        if fact.status == .legend { parts.append(String(localized: "Legend, not a proven fact")) }
        if fact.status == .disputed { parts.append(String(localized: "Disputed")) }
        parts.append(fact.short)
        return parts.joined(separator: ". ")
    }
}

private struct RailButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RailLabel(symbol: symbol, title: title)
        }
        .buttonStyle(.plain)
    }
}

private struct RailLabel: View {
    let symbol: String
    let title: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 44, minHeight: 36)
            if !typeSize.isAccessibilitySize {
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        .contentShape(Rectangle())
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
    @Environment(\.safeAreaInsets) fileprivate var safeArea
    fileprivate var safeTop: CGFloat { safeArea.top }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let picture {
                Image(uiImage: picture.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(zoomed ? 1.09 : 1.0, anchor: .center)
                    .id(picture.image)
                    .transition(.opacity)
                sourceLabel(picture.source)
            } else {
                VisualPlaceholder(kind: place.spot.kind, isLoading: !didFail,
                                  message: didFail ? String(localized: "No picture right now") : nil)
            }
        }
        .task(id: place.id) {
            picture = nil
            didFail = false
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

extension FeedPicture {
    /// Says what the picture is, and credits Apple, in the corner.
    fileprivate func sourceLabel(_ source: SpotVisuals.Source) -> some View {
        Text(source == .lookAround ? "Look Around" : "3D map")
            .font(.caption2.weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.top, safeTop + 64)
            .padding(.trailing, 14)
    }
}

extension EnvironmentValues {
    /// The window's safe area, for layouts that ignore it but still need to clear system bars.
    @Entry var safeAreaInsets = EdgeInsets()
}
