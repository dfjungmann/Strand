import SwiftUI

@main
struct StrandWatchApp: App {
    @State private var viewModel = WatchTideViewModel()

    init() {
        #if os(watchOS)
        _ = WatchSettingsSync.shared
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchTideClockView(viewModel: viewModel)
                .task {
                    WatchSettingsSync.shared.applyStoredContext()
                    await viewModel.loadTides()
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchSettingsDidUpdate)) { _ in
                    Task { @MainActor in await viewModel.loadTides() }
                }
        }
    }
}
