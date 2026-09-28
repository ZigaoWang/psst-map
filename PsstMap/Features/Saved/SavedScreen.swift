import SwiftUI

struct SavedScreen: View {
    @Environment(AppModel.self) private var app
    @State private var detailPlace: Place?
    @State private var showsAbout = false

    private var savedPlaces: [Place] {
        app.saved.ids.compactMap { app.catalog.place(id: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if savedPlaces.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(String(localized: "About Psst"))
                }
            }
            .sheet(item: $detailPlace) { place in
                SpotDetailView(place: place)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsAbout) {
                AboutView()
            }
            #if DEBUG
            .onAppear { if UserDefaults.standard.string(forKey: "debug.sheet") == "about" { showsAbout = true } }
            #endif
        }
    }

    private var list: some View {
        List {
            ForEach(savedPlaces) { place in
                Button { detailPlace = place } label: {
                    SavedRow(place: place)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        withAnimation { app.saved.remove(place.id) }
                    } label: {
                        Label("Remove", systemImage: "bookmark.slash")
                    }
                }
                .contextMenu {
                    Button { app.showOnMap(place) } label: { Label("Show on map", systemImage: "map") }
                    ShareLink(item: ShareText.text(for: place)) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { app.saved.remove(place.id) } label: {
                        Label("Remove", systemImage: "bookmark.slash")
                    }
                }
                .accessibilityAction(named: String(localized: "Remove from saved")) { app.saved.remove(place.id) }
                .accessibilityAction(named: String(localized: "Show on map")) { app.showOnMap(place) }
            }
        }
        .listStyle(.insetGrouped)
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
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.screenBackground)
    }
}

private struct SavedRow: View {
    let place: Place

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            KindTile(kind: place.spot.kind, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.body.weight(.semibold))
                Text(place.leadFact.headline)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
                Text("\(place.areaName), \(place.city)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
