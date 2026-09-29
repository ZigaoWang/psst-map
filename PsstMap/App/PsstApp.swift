import SwiftUI

@main
struct PsstApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await MapDatum.shared.calibrate() }
                .onChange(of: scenePhase) { _, phase in
                    // People cross into and out of mainland China with the app in the background.
                    if phase == .active {
                        Task { await MapDatum.shared.calibrate() }
                        Task { await app.checkForUpdates() }
                    }
                }
                .task {
                    await app.load()
                    #if DEBUG
                    DebugLaunch.apply(to: app)
                    #endif
                }
        }
    }
}
