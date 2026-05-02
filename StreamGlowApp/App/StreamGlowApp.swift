import SwiftUI

@main
struct StreamGlowApp: App {
    @StateObject private var model = StreamGlowModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1180, minHeight: 780)
        }
        .windowResizability(.contentMinSize)
    }
}
