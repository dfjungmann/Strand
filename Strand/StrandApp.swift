import SwiftUI

@main
struct StrandApp: App {
    init() {
        #if os(iOS)
        _ = WatchSettingsSync.shared
        WatchSettingsSync.shared.pushFromPhone()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
