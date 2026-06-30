import SwiftUI

struct ContentView: View {
    @State private var viewModel = TideViewModel()
    @AppStorage("last_selected_tab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TableView(viewModel: viewModel, selectedTab: $selectedTab)
                .tabItem { Label("Tabelle", systemImage: "list.bullet") }
                .tag(0)

            TideClockView(viewModel: viewModel, selectedTab: $selectedTab)
                .tabItem { Label("Uhr", systemImage: "clock") }
                .tag(1)

            VerlaufView(viewModel: viewModel)
                .tabItem { Label("Verlauf", systemImage: "chart.xyaxis.line") }
                .tag(2)

            WeatherForecastView()
                .tabItem { Label("Wetter", systemImage: "cloud.sun.fill") }
                .tag(3)

            // Radar-Tab: nur eingebunden wenn INCLUDE_RADAR Compiler-Flag gesetzt ist.
            // Aktivieren: Xcode → Build Settings → Swift Compiler - Custom Flags →
            //   Other Swift Flags → "-DINCLUDE_RADAR" hinzufügen
            #if INCLUDE_RADAR
            WeatherMapView(selectedTab: $selectedTab)
                .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
                .tag(4)
            #endif

            SettingsView(viewModel: viewModel)
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(5)
        }
        .background(TabBarReselectObserver(tabIndex: 1, notificationName: .clockTabReselected))
        .onAppear { selectedTab = Self.normalizedTab(selectedTab) }
        .task { await viewModel.loadTides() }
        .onAppear { WatchSettingsSync.shared.pushFromPhone() }
    }

    /// Gültiger Tab-Index (Radar-Tab nur wenn eingebunden).
    private static func normalizedTab(_ tab: Int) -> Int {
        #if INCLUDE_RADAR
        (0...5).contains(tab) ? tab : 0
        #else
        switch tab {
        case 0, 1, 2, 3, 5: tab
        case 4: 3
        default: 0
        }
        #endif
    }
}

#Preview {
    ContentView()
}
