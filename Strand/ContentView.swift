import SwiftUI

struct ContentView: View {
    @State private var viewModel = TideViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TableView(viewModel: viewModel)
                .tabItem {
                    Label("Tabelle", systemImage: "list.bullet")
                }
                .tag(0)

            ChartView(viewModel: viewModel)
                .tabItem {
                    Label("Diagramm", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(1)

            BeachWalkView(viewModel: viewModel)
                .tabItem {
                    Label("Strandgang", systemImage: "figure.walk")
                }
                .tag(2)

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                .tag(3)
        }
        .task {
            await viewModel.loadTides()
        }
    }
}

#Preview {
    ContentView()
}
