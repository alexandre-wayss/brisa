import SwiftUI

@main
struct BrisaApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup { ContentView(model: model) }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1080, height: 770)
        MenuBarExtra("Brisa", systemImage: "wind") {
            MenuBarPlayerView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
