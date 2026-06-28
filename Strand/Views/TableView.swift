import SwiftUI

struct TableView: View {
    let viewModel: TideViewModel
    @Binding var selectedTab: Int

    @State private var selectedDay: TideDay?
    @AppStorage("showAstronomy")    private var showAstronomy  = true
    @AppStorage("showWeather")      private var showWeather    = true
    @AppStorage("showWaves")        private var showWaves      = true
    @AppStorage("table_show_wind")  private var showWind       = false
    // Read font size once at TableView level so only one view re-renders when
    // it changes, rather than all 10 CompactDayRow instances simultaneously.
    // Simultaneous height changes in a List can accidentally trigger the
    // UIRefreshControl (pull-to-refresh) when the list is scrolled to the top.
    @AppStorage("tableFontSize") private var tableFontSize = 14.0

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.tideDays.isEmpty {
                    emptyView
                } else {
                    tideList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedDay) { day in
                DayDetailView(day: day, viewModel: viewModel)
                    .interactiveDismissDisabled(false)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Strand & Meer")
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            showAstronomy.toggle()
                        } label: {
                            Image(systemName: showAstronomy ? "sun.horizon.fill" : "sun.horizon")
                                .foregroundStyle(showAstronomy ? .yellow : .secondary)
                        }
                        Button {
                            showWeather.toggle()
                        } label: {
                            Image(systemName: showWeather ? "cloud.sun.fill" : "cloud.sun")
                                .foregroundStyle(showWeather ? .blue : .secondary)
                        }
                        Button {
                            showWaves.toggle()
                        } label: {
                            Image(systemName: showWaves ? "water.waves" : "water.waves.slash")
                                .foregroundStyle(showWaves ? .teal : .secondary)
                        }
                        Button {
                            showWind.toggle()
                        } label: {
                            Image(systemName: showWind ? "wind" : "wind")
                                .foregroundStyle(showWind ? .blue : .secondary)
                        }
                    }
                }
            }
        }
        // Swipe left → switch to Uhr tab (tab 1)
        // simultaneousGesture lets the List scroll vertically as usual;
        // only a clearly horizontal drag (|dx| > 2×|dy|, > 60 pt) triggers the tab switch.
        .simultaneousGesture(
            DragGesture(minimumDistance: 60)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    if v.translation.width < -60 { withAnimation { selectedTab = 1 } }
                }
        )
    }

    // MARK: - List

    private var tideList: some View {
        List {
                ForEach(Array(viewModel.tideDays.enumerated()), id: \.offset) { index, day in
                CompactDayRow(day: day, viewModel: viewModel,
                              showAstronomy: showAstronomy,
                              showWeather: showWeather,
                              showWaves: showWaves,
                              showWind: showWind,
                              fontSize: tableFontSize,
                              isAlternate: index % 2 == 1)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(index % 2 == 1 ? Color.primary.opacity(0.04) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDay = day }
            }

            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Puerto de la Luz\(offsetDescription) · Kanarische Zeit")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.reload()
        }
    }

    private var offsetDescription: String {
        let offset = viewModel.timeOffsetMinutes
        guard offset != 0 else { return "" }
        return offset < 0 ? " −\(abs(offset)) Min." : " +\(offset) Min."
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Lade Gezeitendaten…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "Keine Daten",
            systemImage: "wave.3.right",
            description: Text(viewModel.errorMessage ?? "Tippe auf Aktualisieren")
        )
    }


}

// MARK: - Compact Day Row

struct CompactDayRow: View {
    let day: TideDay
    let viewModel: TideViewModel
    var showAstronomy: Bool = true
    var showWeather: Bool   = true
    var showWaves: Bool     = true
    var showWind: Bool      = false
    var fontSize: Double    = 14.0
    var isAlternate: Bool   = false

    private var bestBeachWalkColor: Color? {
        if day.events.contains(where: { $0.beachWalkStatus == .safe })   { return Color(.systemGreen) }
        if day.events.contains(where: { $0.beachWalkStatus == .likely }) { return Color(.systemYellow) }
        return nil
    }

    private var astronomy: AstronomyData {
        AstronomyService.data(for: day.date)
    }

    private func precipColor(_ prob: Int) -> Color {
        switch prob {
        case 0..<20:  return .green
        case 20..<50: return .orange
        default:      return .blue
        }
    }

    private func cloudIcon(_ cover: Int) -> String {
        switch cover {
        case 0..<20:  return "sun.max.fill"
        case 20..<50: return "cloud.sun.fill"
        case 50..<80: return "cloud.fill"
        default:      return "cloud.heavyrain.fill"
        }
    }

    private func cloudColor(_ cover: Int) -> Color {
        switch cover {
        case 0..<20:  return .yellow
        case 20..<50: return .orange
        case 50..<80: return .gray
        default:      return .blue
        }
    }

    private func cloudLabel(_ cover: Int) -> String {
        switch cover {
        case 0..<20:  return "sonnig"
        case 20..<50: return "teils bewölkt"
        case 50..<80: return "bewölkt"
        default:      return "stark bewölkt"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {

            // ── Tag-Header ──
            HStack {
                HStack(spacing: 4) {
                    Text(viewModel.formatDayHeader(day.date))
                        .font(.headline)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(Capsule())
                Spacer()
                // Wassertemperatur (Tagesmittel) neben dem Titel
                if let waterTemp = viewModel.meanWaterTemp(for: day.date) {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium").foregroundStyle(.teal)
                        Text(String(format: "%.1f°", waterTemp)).foregroundStyle(.teal)
                    }
                    .font(.caption)
                }
                if let beachColor = bestBeachWalkColor {
                    HStack(spacing: 3) {
                        Image(systemName: "beach.umbrella")
                        Text("Strandgang")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(beachColor.opacity(0.2))
                    .foregroundStyle(beachColor)
                    .clipShape(Capsule())
                }
            }

            // ── Spalten: Zeit + Höhe übereinander, Strandgang farbig ──
            HStack(spacing: 4) {
                ForEach(day.events) { event in
                    let isHigh    = event.type == .highTide
                    let tideColor: Color = isHigh ? .blue : .orange
                    // High tide: 2 steps smaller (factor 0.82 ≈ two typography steps)
                    let scale: CGFloat   = isHigh ? 0.82 : 1.0
                    let bgColor: Color = {
                        switch event.beachWalkStatus {
                        case .safe:   return .green
                        case .likely: return .yellow
                        case .none:   return .clear
                        }
                    }()
                    let onBg = event.beachWalkStatus != .none
                    let textOnBg: Color = event.beachWalkStatus == .likely ? .black : .white

                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: isHigh ? "arrow.up" : "arrow.down")
                                .font(.system(size: fontSize * scale * 0.65, weight: .bold))
                                .foregroundStyle(onBg ? textOnBg : tideColor)
                            Text(viewModel.formatTime(event.adjustedTime))
                                .font(.system(size: fontSize * scale, weight: .medium).monospacedDigit())
                                .foregroundStyle(onBg ? textOnBg : .primary)
                        }
                        Text(viewModel.displayHeightFormatted(event.height))
                            .font(.system(size: fontSize * scale * 0.9).monospacedDigit())
                            .foregroundStyle(onBg ? textOnBg : tideColor)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(bgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            // ── Wellenhöhe zu den Tidenzeiten ──
            if showWaves && !viewModel.hourlyMarine.isEmpty {
                HStack(spacing: 4) {
                    ForEach(day.events) { event in
                        let wh = viewModel.waveHeight(at: event.adjustedTime)
                        HStack(spacing: 3) {
                            Image(systemName: "water.waves")
                                .font(.system(size: fontSize * 0.65))
                                .foregroundStyle(.teal)
                            if let wh {
                                Text(String(format: "%.1fm", wh))
                                    .font(.system(size: fontSize * 0.9).monospacedDigit())
                                    .foregroundStyle(.teal)
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
            }

            // ── Windstärke: Maximum pro Tages-Viertel (0–6h / 6–12h / 12–18h / 18–24h) ──
            if showWind && !viewModel.hourlyWeather.isEmpty {
                let quarters = viewModel.maxWindSpeedPerQuarter(for: day.date)
                let labels = ["0–6h", "6–12h", "12–18h", "18–24h"]
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { q in
                        VStack(spacing: 1) {
                            Text(labels[q])
                                .font(.system(size: fontSize * 0.65))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                Image(systemName: "wind")
                                    .font(.system(size: fontSize * 0.65))
                                    .foregroundStyle(.blue)
                                if let ws = quarters[q] {
                                    Text(String(format: "%.0f km/h", ws))
                                        .font(.system(size: fontSize * 0.9).monospacedDigit())
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("—")
                                        .font(.system(size: fontSize * 0.9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
            }

            // ── Sonne & Mond ──
            if showAstronomy {
                HStack(spacing: 16) {
                    if let rise = astronomy.sunrise {
                        HStack(spacing: 4) {
                            Image(systemName: "sunrise.fill").foregroundStyle(.yellow)
                            Text(viewModel.formatTime(rise)).monospacedDigit()
                        }
                    }
                    if let set = astronomy.sunset {
                        HStack(spacing: 4) {
                            Image(systemName: "sunset.fill").foregroundStyle(.orange)
                            Text(viewModel.formatTime(set)).monospacedDigit()
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text(astronomy.moonPhase.emoji)
                        Text(astronomy.moonPhase.rawValue).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            // ── Wetter ──
            if showWeather, let wx = viewModel.weather(for: day.date) {
                HStack(spacing: 14) {
                    // Temperatur
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium").foregroundStyle(.red)
                        Text("\(Int(wx.maxTemp.rounded()))°").foregroundStyle(.red)
                        Text("/").foregroundStyle(.secondary)
                        Text("\(Int(wx.minTemp.rounded()))°").foregroundStyle(.blue)
                    }
                    // Regen
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill").foregroundStyle(precipColor(wx.precipProb))
                        Text("\(wx.precipProb) %").foregroundStyle(precipColor(wx.precipProb))
                    }
                    // Sonnenstunden
                    HStack(spacing: 3) {
                        Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f h", wx.sunshineHours)).foregroundStyle(.primary)
                    }
                    // Bewölkung
                    HStack(spacing: 3) {
                        Image(systemName: cloudIcon(wx.cloudCover))
                            .foregroundStyle(cloudColor(wx.cloudCover))
                        Text("\(wx.cloudCover) %").foregroundStyle(.secondary)
                        Text(cloudLabel(wx.cloudCover)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)
            }

            Divider()
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
        .background(isAlternate ? Color.primary.opacity(0.04) : Color.clear)
    }
}
