import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("onboarding.completed") private var hasSeenWelcome = false

    var body: some View {
        switch app.loadState {
        case .loading:
            LoadingView()
        case .failed(let message):
            LoadFailedView(message: message) {
                Task { await app.load() }
            }
        case .loaded:
            tabs
                .fullScreenCover(isPresented: Binding(get: { !hasSeenWelcome }, set: { hasSeenWelcome = !$0 })) {
                    WelcomeView { hasSeenWelcome = true }
                }
        }
    }

    private var tabs: some View {
        @Bindable var app = app
        return TabView(selection: $app.selectedTab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(AppModel.Tab.map)
            FeedScreen()
                .tabItem { Label("Feed", systemImage: "rectangle.stack") }
                .tag(AppModel.Tab.feed)
            SavedScreen()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(AppModel.Tab.saved)
        }
        .tint(.primary)
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Wordmark(size: 56, color: Theme.ink)
            ProgressView()
                .tint(Theme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Loading places"))
    }
}

private struct LoadFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Wordmark(size: 48, color: Theme.ink)
            Text("Something went quiet")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.ink.opacity(0.7))
                .multilineTextAlignment(.center)
            Text("Try again. If it keeps happening, reinstalling Psst will fix it.")
                .font(.footnote)
                .foregroundStyle(Theme.ink.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}
