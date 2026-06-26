import SwiftUI
import Charts

// MARK: - Container with swipe navigation

struct DayDetailView: View {
    let initialDay: TideDay
    let viewModel: TideViewModel

    @State private var currentIndex: Int
    @State private var dayCount: Int = 2
    @State private var showWind: Bool = true
    @Environment(\.dismiss) private var dismiss

    init(day: TideDay, viewModel: TideViewModel) {
        self.initialDay = day
        self.viewModel = viewModel
        let idx = viewModel.tideDays.firstIndex(where: { $0.id == day.id }) ?? 0
        self._currentIndex = State(initialValue: idx)
    }

    private var currentDay: TideDay {
        viewModel.tideDays[safe: currentIndex] ?? initialDay
    }

    private var dayCountLabel: String {
        dayCount == 1 ? "1 Tag" : "\(dayCount) Tage"
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.tideDays.enumerated()), id: \.offset) { idx, day in
                    DayDetailContent(day: day, viewModel: viewModel,
                                     dayCount: $dayCount, showWind: $showWind)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(viewModel.formatDayHeader(currentDay.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation { currentIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentIndex == 0)

                        Button {
                            withAnimation { currentIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentIndex >= viewModel.tideDays.count - 1)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation { showWind.toggle() }
                        } label: {
                            Image(systemName: "wind")
                                .foregroundStyle(showWind ? .teal : .secondary)
                        }
                        Button("Schließen") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onDisappear { dayCount = 2 }
    }
}

// MARK: - Content for one day

private struct DayDetailContent: View {
    let day: TideDay
    let viewModel: TideViewModel
    @Binding var dayCount: Int
    @Binding var showWind: Bool
    @State private var showDayPicker = false
    @State private var viewSize: CGSize = .zero

    private var displayDays: [TideDay] {
        guard let idx = viewModel.tideDays.firstIndex(where: { $0.id == day.id }) else {
            return [day]
        }
        return Array(viewModel.tideDays[idx...].prefix(dayCount))
    }

    private var hourly: [HourlyWeather] {
        viewModel.hourlyWeather(from: Calendar.current.startOfDay(for: day.date),
                                dayCount: dayCount)
    }

    private var marine: [HourlyMarine] {
        viewModel.marineData(from: Calendar.current.startOfDay(for: day.date),
                             dayCount: dayCount)
    }

    private var marineWaterTemps: [(time: Date, temp: Double)] {
        marine.compactMap { m in
            guard let t = m.waterTemp else { return nil }
            return (m.time, t)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        tideChartCard
                        if !hourly.isEmpty {
                            tempChartCard
                            atmosphereChartCard
                            if showWind {
                                windChartCard
                            }
                        }
                    }
                    .padding(12)
                }

                // Hint footer
                Text("long press  ·  \(dayCount == 1 ? "1 Tag" : "\(dayCount) Tage")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            // Measure view size for picker positioning
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { viewSize = geo.size }
                }
            )
            // Detect long press – no DragGesture here so the TabView page
            // swipe (swipe between days) can work without interference
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showDayPicker = true
                        }
                    }
            )

            if showDayPicker {
                // Tap-away backdrop
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showDayPicker = false
                        }
                    }

                DayCountPicker(dayCount: $dayCount) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showDayPicker = false
                    }
                }
                .position(pickerPosition)
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDayPicker)
    }

    // Fixed picker position: centred horizontally, upper third of the view
    private var pickerPosition: CGPoint {
        let x = viewSize.width  > 0 ? viewSize.width  / 2 : UIScreen.main.bounds.width  / 2
        let y = viewSize.height > 0 ? viewSize.height * 0.30 : 200
        return CGPoint(x: x, y: y)
    }

    // MARK: - Tide Chart Card

    private var tideChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gezeiten")
                .font(.headline)
                .padding(.horizontal, 4)
            tideChart
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var tideChart: some View {
        let points = viewModel.chartPoints(for: displayDays)
        let events = displayDays.flatMap { $0.events }
        let bounds = viewModel.dayBoundaries(for: displayDays)
        let maxH   = (events.map { $0.height }.max() ?? 2.0) + 0.4

        return Chart {
            ForEach(bounds, id: \.self) { b in
                RuleMark(x: .value("Tag", b))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color(.systemGray4))
            }
            RuleMark(y: .value("Sicher", viewModel.beachWalkThresholdSafe))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.green.opacity(0.8))
                .annotation(position: .top, alignment: .leading) {
                    Text("Sicher \(String(format: "%.1f m", viewModel.beachWalkThresholdSafe))")
                        .font(.caption2).foregroundStyle(.green).padding(.leading, 4)
                }
            RuleMark(y: .value("Wahrsch.", viewModel.beachWalkThresholdLikely))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.yellow.opacity(0.9))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Wahrsch. \(String(format: "%.1f m", viewModel.beachWalkThresholdLikely))")
                        .font(.caption2).foregroundStyle(.orange).padding(.trailing, 4)
                }
            // Beach walk windows (±1.5h around qualifying low tides)
            ForEach(events.filter { $0.type == .lowTide && $0.beachWalkStatus != .none }) { e in
                let start = e.adjustedTime.addingTimeInterval(-90 * 60)
                let end   = e.adjustedTime.addingTimeInterval( 90 * 60)
                let color: Color = e.beachWalkStatus == .safe ? .green : .yellow
                RectangleMark(
                    xStart: .value("Start", start),
                    xEnd:   .value("End",   end),
                    yStart: .value("0",     0.0),
                    yEnd:   .value("Top",   maxH)
                )
                .foregroundStyle(color.opacity(0.18))
            }

            ForEach(points) { p in
                AreaMark(x: .value("Zeit", p.time), yStart: .value("0", 0), yEnd: .value("H", p.height))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue.opacity(0.25), .blue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(points) { p in
                LineMark(x: .value("Zeit", p.time), y: .value("H", p.height))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(events) { e in
                PointMark(x: .value("Zeit", e.adjustedTime), y: .value("H", e.height))
                    .foregroundStyle(e.type == .highTide ? Color.blue : Color.orange)
                    .symbolSize(60)
                    .annotation(position: e.type == .highTide ? .top : .bottom, spacing: 2) {
                        VStack(spacing: 1) {
                            Text(viewModel.formatTime(e.adjustedTime))
                                .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                            Text(e.heightFormatted)
                                .font(.system(size: 9).monospacedDigit()).fontWeight(.semibold)
                                .foregroundStyle(e.type == .highTide ? .blue : .orange)
                        }
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 0.5)) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(String(format: "%.1f", d)).font(.caption2) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { v in
                AxisGridLine()
                AxisValueLabel(centered: false) {
                    if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                }
            }
        }
        .chartYScale(domain: 0...maxH)
        .frame(height: 170)
    }

    // MARK: - Temperature Chart Card

    private var tempChartCard: some View {
        let temps    = hourly
        let wtemps   = marineWaterTemps
        let hasWater = !wtemps.isEmpty
        let allTemps = temps.map(\.temp) + wtemps.map(\.temp)
        let minT     = (allTemps.min() ?? 15) - 1
        let maxT     = (allTemps.max() ?? 30) + 1
        let bounds   = viewModel.dayBoundaries(for: displayDays)

        // Flat series for LineMark – unique labels prevent Charts from merging series
        let airPoints: [TempPoint] = temps.map {
            TempPoint(id: "a-\($0.id)", time: $0.time, value: $0.temp, series: "Luft")
        }
        let waterPoints: [TempPoint] = wtemps.enumerated().map { idx, wt in
            TempPoint(id: "w-\(idx)", time: wt.time, value: wt.temp, series: "Wasser")
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Temperatur").font(.headline)
                Spacer()
                if hasWater {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.red).frame(width: 14, height: 3)
                            Text("Luft").font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.teal).frame(width: 14, height: 3)
                            Text("Wasser").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)

            Chart {
                ForEach(bounds, id: \.self) { b in
                    RuleMark(x: .value("Tag", b))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color(.systemGray4))
                }
                // Area fill beneath air temperature (explicit gradient, not part of legend scale)
                ForEach(airPoints) { p in
                    AreaMark(
                        x: .value("Zeit", p.time),
                        yStart: .value("Min", minT),
                        yEnd: .value("T", p.value)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [.red.opacity(0.2), .orange.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                }
                // Air temperature line – colour driven by foregroundStyle(by:)
                ForEach(airPoints) { p in
                    LineMark(x: .value("Zeit", p.time), y: .value("T", p.value))
                        .foregroundStyle(by: .value("Serie", p.series))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                // Water temperature line – same scale key "Wasser"
                ForEach(waterPoints) { p in
                    LineMark(x: .value("Zeit", p.time), y: .value("T", p.value))
                        .foregroundStyle(by: .value("Serie", p.series))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale(["Luft": Color.red, "Wasser": Color.teal])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text("\(Int(d))°").font(.caption2) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: minT...maxT)
            .frame(height: 128)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Atmosphere Chart Card (humidity, cloud cover, precip probability)

    private var atmosphereChartCard: some View {
        let data   = hourly
        let bounds = viewModel.dayBoundaries(for: displayDays)
        let atmoPoints: [AtmoPoint] = data.flatMap { h in
            let ts = "\(h.time.timeIntervalSince1970)"
            return [
                AtmoPoint(id: ts + "-f", time: h.time, value: h.humidity,   series: "Feuchte"),
                AtmoPoint(id: ts + "-w", time: h.time, value: h.cloudCover, series: "Wolken"),
                AtmoPoint(id: ts + "-r", time: h.time, value: h.precipProb, series: "Regen"),
            ]
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Atmosphäre")
                .font(.headline)
                .padding(.horizontal, 4)

            HStack(spacing: 0) {
                Label("Luftfeuchte", systemImage: "humidity")
                    .font(.caption).foregroundStyle(.teal)
                Spacer()
                Label("Bewölkung", systemImage: "cloud")
                    .font(.caption).foregroundStyle(Color(.systemGray))
                Spacer()
                Label("Regenwahrsch.", systemImage: "umbrella")
                    .font(.caption).foregroundStyle(.blue)
            }
            .padding(.horizontal, 4)

            Chart {
                ForEach(bounds, id: \.self) { b in
                    RuleMark(x: .value("Tag", b))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color(.systemGray4))
                }
                ForEach(atmoPoints) { p in
                    LineMark(
                        x: .value("Zeit", p.time),
                        y: .value("%", p.value)
                    )
                    .foregroundStyle(by: .value("Serie", p.series))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale([
                "Feuchte": Color.teal,
                "Wolken":  Color(.systemGray2),
                "Regen":   Color.blue,
            ])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Int.self) { Text("\(d)%").font(.caption2) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 128)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Wind Chart Card

    private func windArrow(_ degrees: Int) -> String {
        // degrees = direction FROM which wind blows (meteorological)
        // arrow points TOWARD where wind goes
        let arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
        return arrows[Int((Double(degrees) + 22.5) / 45.0) % 8]
    }

    private var windChartCard: some View {
        let windData = hourly
        let maxWind  = max((windData.map(\.windSpeed).max() ?? 20) * 1.15, 5.0)
        let bounds   = viewModel.dayBoundaries(for: displayDays)
        let maxV     = windData.map(\.windSpeed).max() ?? 0
        // one arrow every 3 h
        let dirPoints: [HourlyWeather] = windData.enumerated()
            .filter { $0.offset % 3 == 0 }
            .map(\.element)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wind")
                    .font(.headline)
                Spacer()
                Text("max. \(Int(maxV.rounded())) km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Chart {
                ForEach(bounds, id: \.self) { b in
                    RuleMark(x: .value("Tag", b))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color(.systemGray4))
                }
                ForEach(windData) { h in
                    AreaMark(
                        x: .value("Zeit", h.time),
                        yStart: .value("0", 0),
                        yEnd: .value("km/h", h.windSpeed)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [.teal.opacity(0.30), .teal.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(windData) { h in
                    LineMark(x: .value("Zeit", h.time), y: .value("km/h", h.windSpeed))
                        .foregroundStyle(.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text("\(Int(d))").font(.caption2) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: 0...maxWind)
            .frame(height: 110)

            // Wind direction arrows aligned with chart x-axis
            HStack(spacing: 0) {
                ForEach(dirPoints) { h in
                    VStack(spacing: 2) {
                        Text(windArrow(h.windDirection))
                            .font(.system(size: 14))
                            .foregroundStyle(.teal)
                        Text("\(Int(h.windSpeed.rounded()))")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - X-Axis Helpers

    private var xAxisValues: [Date] {
        guard let startDay = displayDays.first?.date else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let midnight = cal.startOfDay(for: startDay)
        // 12h steps for 1-3 days, 24h steps for 4+ days
        let stepHours = dayCount <= 3 ? 12 : 24
        let count = dayCount * (24 / stepHours) + 1
        return (0..<count).map { cal.date(byAdding: .hour, value: $0 * stepHours, to: midnight)! }
    }

    private func xLabel(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let hour = cal.component(.hour, from: date)
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EE"
        dayFmt.locale = Locale(identifier: "de_DE")
        dayFmt.timeZone = TideService.canaryIslandsTimeZone
        return hour == 0 ? dayFmt.string(from: date) : "\(hour):00"
    }
}

// MARK: - Day count picker overlay

private struct DayCountPicker: View {
    @Binding var dayCount: Int
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Tage anzeigen")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(1...10, id: \.self) { n in
                    Button {
                        dayCount = n
                        onSelect()
                    } label: {
                        Text("\(n)")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(
                                dayCount == n
                                    ? Color.accentColor
                                    : Color(.systemGray5)
                            )
                            .foregroundStyle(dayCount == n ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(dayCount == n ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25), value: dayCount)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
    }
}

// MARK: - AtmoPoint for multi-series atmosphere chart

private struct AtmoPoint: Identifiable {
    let id: String
    let time: Date
    let value: Int
    let series: String
}

// MARK: - TempPoint for multi-series temperature chart

private struct TempPoint: Identifiable {
    let id: String
    let time: Date
    let value: Double
    let series: String   // "Luft" | "Wasser"
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
