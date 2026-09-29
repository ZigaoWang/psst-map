import SwiftUI

/// The places someone has kept, as a grid of pictures, newest first.
struct SavedScreen: View {
    @Environment(AppModel.self) private var app
    @State private var detailPlace: Place?
    @State private var showsAbout = false
    @Namespace private var zoom
    @Environment(\.dynamicTypeSize) private var typeSize

    private var savedPlaces: [Place] {
        app.saved.ids.compactMap { app.catalog.place(id: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if savedPlaces.isEmpty {
                    empty
                } else {
                    grid
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.screenBackground)
        .placePresentation($detailPlace, namespace: zoom)
        .sheet(isPresented: $showsAbout) {
            SettingsView()
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.string(forKey: "debug.sheet") == "about" { showsAbout = true } }
        #endif
    }

    /// Title and the About button on one line, so the button never pushes the title down.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if !savedPlaces.isEmpty {
                    Text(savedPlaces.count == 1 ? "1 place" : "\(savedPlaces.count) places")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                showsAbout = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .floatingButtonStyle(circle: true)
            .foregroundStyle(.primary)
            .accessibilityLabel(String(localized: "Settings"))
            .padding(.top, 4)
        }
        .padding(.top, 12)
    }

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(savedPlaces) { place in
                Button { detailPlace = place } label: {
                    SavedCard(place: place)
                }
                .buttonStyle(PressableButtonStyle())
                .placeZoomSource(place.id, in: zoom)
                .contextMenu {
                    Button { app.showOnMap(place) } label: { Label("Show on map", systemImage: "map") }
                    ShareLink(item: ShareText.text(for: place)) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        withAnimation(.snappy) { app.saved.remove(place.id) }
                    } label: {
                        Label("Remove", systemImage: "bookmark.slash")
                    }
                }
                .accessibilityAction(named: String(localized: "Remove from saved")) { app.saved.remove(place.id) }
                .accessibilityAction(named: String(localized: "Show on map")) { app.showOnMap(place) }
            }
        }
        .animation(.snappy, value: app.saved.ids)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Nothing saved yet")
                .font(.title2.weight(.bold))
            Text("When a place surprises you, tap Save and it will wait for you here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                app.selectedTab = .feed
            } label: {
                Text("Browse the feed")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 120)
        .frame(maxWidth: .infinity)
    }
}

/// A saved place: its picture, its name, and the story that made it worth keeping.
private struct SavedCard: View {
    let place: Place
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaceThumbnail(place: place)
                .aspectRatio(4 / 5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(place.spot.kind.color)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .padding(10)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(app.leadFact(for: place).headline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Opens the full story"))
    }
}
