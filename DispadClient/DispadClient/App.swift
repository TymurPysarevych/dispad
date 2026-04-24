import SwiftUI

@main
struct DispadClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .persistentSystemOverlays(.hidden)
                .statusBar(hidden: true)
        }
    }
}
