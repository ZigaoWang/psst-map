import SwiftUI

/// A place's photos, one page each. Historic photos carry their year.
struct PhotoPager: View {
    let photos: [Photo]
    @Binding var selection: String?
    let onOpen: (Photo) -> Void

    var body: some View {
        TabView(selection: $selection) {
            ForEach(photos) { photo in
                PlacePhotoImage(photo: photo, size: .full)
                    .overlay(alignment: .topLeading) {
                        if photo.kind == .historic, let year = photo.year {
                            YearBadge(year: year)
                                .padding(.leading, 16)
                                .padding(.top, 60)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(photo) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(String(localized: "Opens the photo full screen"))
                    .tag(Optional(photo.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
    }
}

struct YearBadge: View {
    let year: Int

    var body: some View {
        Text(String(year))
            .font(.footnote.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityLabel(String(localized: "Taken in \(String(year))"))
    }
}

/// The credit for a photo. Tapping it opens the photo's source page, where the full license is.
struct PhotoCredit: View {
    let photo: Photo
    var color: Color = .secondary

    var body: some View {
        Link(destination: photo.credit.sourceUrl) {
            HStack(spacing: 3) {
                Text(photo.creditLine)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(color)
        }
        .accessibilityHint(String(localized: "Opens where the photo came from"))
    }
}

/// One photo, full screen, fitted and zoomable, with its description and credit.
struct PhotoViewer: View {
    let photo: Photo

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(min(max(zoom * pinch, 1), 4))
                    .gesture(MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in withAnimation(.snappy) { zoom = min(max(zoom * value.magnification, 1), 4) } })
                    .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = zoom > 1 ? 1 : 2.5 } }
                    .accessibilityLabel(photo.alt)
                    .accessibilityAddTraits(.isImage)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .floatingButtonStyle(circle: true)
            .padding(16)
            .accessibilityLabel(String(localized: "Close"))
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text(photo.alt)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
                PhotoCredit(photo: photo, color: .white.opacity(0.7))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            .opacity(zoom > 1 ? 0 : 1)
        }
        .task {
            let screen = max(AppWindow.size.width, AppWindow.size.height) * displayScale
            image = await PhotoLoader.shared.image(photo, size: .full, maxPixels: screen)
        }
    }
}
