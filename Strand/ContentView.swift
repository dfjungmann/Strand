import SwiftUI

struct ContentView: View {
    @State private var viewModel   = TideViewModel()
    @State private var selectedTab = 0

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

            WeatherMapView(selectedTab: $selectedTab)
                .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
                .tag(4)

            SettingsView(viewModel: viewModel)
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(5)
        }
        .task { await viewModel.loadTides() }
    }
}

#Preview {
    ContentView()
}
