import SwiftUI

@main
struct PsstApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.load() }
        }
    }
}
