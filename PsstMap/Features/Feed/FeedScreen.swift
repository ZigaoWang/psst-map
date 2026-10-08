import CoreLocation
import SwiftUI

/// The vertical, full-screen feed of places.
struct FeedScreen: View {
    @Environment(AppModel.self) private var app
    @State private var scope: FeedScope = .everywhere
    @State private var items: [Place] = []
    @State private var currentID: String?
    @State private var detailPlace: Place?
    @Namespace private var zoom
    @State private var isLocating = false
    @State private var locationMessage: String?
    @State private var pageSize: CGSize?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let endID = "feed.end"

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                              height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                    .onAppear { pageSize = size }
                    .onChange(of: size) { pageSize = size }
                if items.isEmpty {
                    emptyState
                } else {
                    pages(size: size)
                        .environment(\.safeAreaInsets, EdgeInsets(top: proxy.safeAreaInsets.top,
                                                                  leading: proxy.safeAreaInsets.leading,
                                                                  bottom: proxy.safeAreaInsets.bottom,
                                                                  trailing: proxy.safeAreaInsets.trailing))
                }
                VStack(spacing: 10) {
                    scopeBar
                    if let locationMessage {
                        Text(locationMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .floatingSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 32)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onTapGesture { self.locationMessage = nil }
                            .task(id: locationMessage) {
                                try? await Task.sleep(for: .seconds(5))
                                withAnimation { self.locationMessage = nil }
                            }
                    }
                }
                .animation(.snappy, value: locationMessage)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(true)
        // The feed is always dark, so the tab bar above it must be too, or its items vanish.
        .toolbarColorScheme(.dark, for: .tabBar)
        .modifier(DarkTabBarBackground())
        .placePresentation($detailPlace, namespace: zoom)
        .onAppear { if items.isEmpty { rebuild() } }
        // New content or different filters keep the reader where they are; a new scope starts over.
        .onChange(of: contentKey) { rebuild(keepingPosition: true) }
        .onChange(of: scope) { rebuild() }
        .onChange(of: currentID) { _, id in handlePageChange(to: id) }
        .sensoryFeedback(.selection, trigger: currentID)
    }

    private func pages(size: CGSize) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(items) { place in
                    FeedCard(place: place, size: size, isActive: currentID == place.id) {
                        detailPlace = place
                    }
                    .frame(width: size.width, height: size.height)
                    .placeZoomSource(place.id, in: zoom)
                    .id(place.id)
                }
                FeedEndCard(count: items.count, scopeName: scopeTitle, onRestart: restart)
                    .frame(width: size.width, height: size.height)
                    .id(Self.endID)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }

    // MARK: Scope

    private var scopeBar: some View {
        Menu {
            Picker("Show places from", selection: $scope) {
                Label("Everywhere", systemImage: "globe").tag(FeedScope.everywhere)
                Label("Near me", systemImage: "location").tag(FeedScope.nearMe)
            }
            ForEach(app.catalog.cities) { city in
                Menu(city.displayName) {
                    Picker(city.displayName, selection: $scope) {
                        Text("All of \(city.displayName)").tag(FeedScope.city(city.id))
                        ForEach(city.neighborhoods) { hood in
                            Text(hood.displayName).tag(FeedScope.neighborhood(hood.id))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isLocating {
                    ProgressView().controlSize(.small)
                }
                Text(scopeTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(minHeight: 24)
        }
        .menuStyle(.button)
        .floatingButtonStyle()
        .padding(.top, 12)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel(String(localized: "Showing places from \(scopeTitle)"))
        .accessibilityHint(String(localized: "Choose where the feed shows places from"))
    }

    private var scopeTitle: String {
        switch scope {
        case .everywhere: String(localized: "Everywhere")
        case .nearMe: String(localized: "Near me")
        case .city(let id): app.catalog.city(id: id)?.displayName ?? String(localized: "Everywhere")
        case .neighborhood(let id): app.catalog.neighborhood(id: id)?.displayName ?? String(localized: "Everywhere")
        }
    }

    private func scopedPlaces() -> [Place] {
        let places: [Place] = switch scope {
        case .everywhere, .nearMe: app.catalog.places
        case .city(let id): app.catalog.places(inCity: id)
        case .neighborhood(let id): app.catalog.places(inNeighborhood: id)
        }
        return places.filter(app.isVisible)
    }

    /// Changes whenever the places the feed could show change: a content update or a filter change.
    private var contentKey: String {
        [app.catalog.contentVersion ?? "",
         app.shownKinds.map(\.rawValue).sorted().joined(separator: ","),
         app.shownCategories.map(\.rawValue).sorted().joined(separator: ",")].joined(separator: "|")
    }

    private func rebuild(keepingPosition: Bool = false) {
        let places = scopedPlaces()
        guard !places.isEmpty else {
            items = []
            return
        }
        if scope == .nearMe {
            isLocating = true
            Task {
                let location = await app.location.currentLocation()
                isLocating = false
                // The reader may have picked somewhere else while their location was being found.
                guard scope == .nearMe else { return }
                guard let location else {
                    locationMessage = app.location.isDenied
                        ? String(localized: "Location is off for Psst. Turn it on in Settings to see what's around you.")
                        : String(localized: "Couldn't find your location. Showing everywhere instead.")
                    scope = .everywhere
                    return
                }
                let nearby = FeedOrder.byDistance(places, from: location)
                show(nearby, keepingPosition: keepingPosition)
                if nearby.first.map({ $0.location.distance(from: location) > 25_000 }) ?? true {
                    locationMessage = String(localized: "Nothing near you yet, so these are the closest places Psst knows.")
                }
            }
        } else {
            show(FeedOrder.order(places, seen: app.seen.ids, seed: app.feedSeed), keepingPosition: keepingPosition)
        }
    }

    private func show(_ places: [Place], keepingPosition: Bool = false) {
        items = places
        if !(keepingPosition && places.contains { $0.id == currentID }) {
            currentID = places.first?.id
        }
        prefetch(after: currentID)
    }

    private func restart() {
        app.seen.forget(items.map(\.id))
        app.feedSeed = UInt64.random(in: 0...UInt64.max)
        withAnimation(reduceMotion ? nil : .smooth) { rebuild() }
    }

    // MARK: Paging

    private func handlePageChange(to id: String?) {
        guard let id, id != Self.endID else { return }
        prefetch(after: id)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if currentID == id { app.seen.markSeen(id) }
        }
    }

    /// Warms the pictures for the next two cards so swiping never lands on a spinner.
    private func prefetch(after id: String?) {
        guard let id, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let upcoming = items.dropFirst(index + 1).prefix(2)
        guard let size = pageSize else { return }
        let pictureSize = FeedCard.pictureSize(for: size)
        for place in upcoming {
            Task(priority: .utility) {
                if let photo = place.spot.currentPhotos.first {
                    await PhotoLoader.shared.prefetch(photo)
                } else {
                    await SpotVisuals.shared.picture(for: place, size: pictureSize, scale: 2, dark: true)
                }
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text("No places here yet")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Try another area, or look everywhere.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
            Button("Show everywhere") { scope = .everywhere }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The last page: a calm stop instead of an endless scroll.
struct FeedEndCard: View {
    let count: Int
    let scopeName: String
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Wordmark(size: 56, color: .white)
            Text("That's everything")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("You've been through all \(count) places in \(scopeName). More are on the way.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button(action: onRestart) {
                Label("Start again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(.white, in: Capsule())
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

/// Before Liquid Glass, the tab bar needs an explicit dark background to pick up the dark scheme.
private struct DarkTabBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(Color.black, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}
