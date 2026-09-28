import MapKit
import SwiftUI

/// The picture at the top of a place page, with one-tap ways into Look Around and the 3D map.
/// It shares its picture with the feed card, so opening a place from the feed shows it instantly.
struct SpotHero: View {
    let place: Place
    let lookAroundScene: MKLookAroundScene?
    let onLookAround: () -> Void
    let onAerial: () -> Void

    @State private var picture: SpotVisuals.Picture?
    @State private var didFail = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let picture {
                        Image(uiImage: picture.image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    } else {
                        VisualPlaceholder(kind: place.spot.kind, isLoading: !didFail,
                                          message: didFail ? String(localized: "No picture right now") : nil)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { lookAroundScene != nil && place.spot.size == .small ? onLookAround() : onAerial() }
                .accessibilityHidden(true)

                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    if lookAroundScene != nil {
                        HeroButton(title: String(localized: "Look Around"), symbol: "binoculars.fill",
                                   action: onLookAround)
                    }
                    HeroButton(title: String(localized: "3D map"), symbol: "cube.fill", action: onAerial)
                }
                .padding(16)
                .animation(.snappy, value: lookAroundScene != nil)
            }
        }
        .task(id: place.id) {
            let size = FeedCard.pictureSize(for: UIScreen.main.bounds.size)
            let result = await SpotVisuals.shared.picture(for: place, size: size, scale: 2, dark: true) { update in
                withAnimation(.easeOut(duration: 0.3)) { picture = update }
            }
            if Task.isCancelled { return }
            didFail = result == nil
        }
    }
}

private struct HeroButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(.black.opacity(0.45), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
