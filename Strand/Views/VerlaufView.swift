import SwiftUI
import Charts

// MARK: - TempChartMode

private enum TempChartMode: String, CaseIterable {
    case continuous
    case dailyMinMax
}

// MARK: - VerlaufView

struct VerlaufView: View {
    let viewModel: TideViewModel

    @AppStorage("verlauf_default_days") private var defaultDays: Int = 5
    @AppStorage("shared_location_id") private var selectedLocationId: String = forecastLocations[0].id
    @State private var displayedDays: Int = 5
    @State private var showTide: Bool = false
    private var selectedLocation: ForecastLocation {
        forecastLocations.first { $0.id == selectedLocationId } ?? forecastLocations[0]
    }
    @State private var showDayPicker = false
    @State private var verlaufHourly: [VerlaufHourlyPoint] = []
    @State private var isLoading = false
    @State private var tempChartMode: TempChartMode = .continuous
    @State private var precipMode: Int = 0   // 0=roh, 1=×max Wkt, 2=×mittlere Wkt

    // MARK: - Data helpers

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: displayedDays, to: today) ?? today
    }

    private var hourlyWeather: [VerlaufHourlyPoint] {
        verlaufHourly.filter { $0.time >= today && $0.time < cutoff }
    }

    private var hourlyMarine: [HourlyMarine] {
        guard selectedLocation.id == "pda" else { return [] }
        return viewModel.hourlyMarine.filter { $0.time >= today && $0.time < cutoff }
    }

    private var visibleTideDays: [TideDay] {
        let cal = Calendar.current
        return viewModel.tideDays.filter { day in
            let dayStart = cal.startOfDay(for: day.date)
            return dayStart >= today && dayStart < cutoff
        }
    }

    private var tideChartPoints: [TideChartPoint] {
        viewModel.chartPoints(for: visibleTideDays)
    }

    private var marineWaterTemps: [(time: Date, temp: Double)] {
        guard selectedLocation.id == "pda" else { return [] }
        return hourlyMarine.compactMap { m in
            guard let t = m.waterTemp else { return nil }
            return (m.time, t)
        }
    }

    private var maxDays: Int {
        let count = verlaufHourly.isEmpty ? viewModel.hourlyWeather.count : verlaufHourly.count
        return max(2, min(14, count / 24))
    }

    // MARK: - Timezone / X-axis helpers

    private var locationTimeZone: TimeZone {
        TimeZone(identifier: selectedLocation.timezone) ?? TideService.canaryIslandsTimeZone
    }

    private var xAxisValues: [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        let midnight = cal.startOfDay(for: today)
        let stepHours = displayedDays <= 3 ? 12 : 24
        let count = displayedDays * (24 / stepHours) + 1
        return (0..<count).map {
            cal.date(byAdding: .hour, value: $0 * stepHours, to: midnight) ?? midnight
        }
    }

    private func xLabel(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        let hour = cal.component(.hour, from: date)
        let fmt = DateFormatter()
        fmt.dateFormat = "EE"
        fmt.locale = Locale(identifier: "de_DE")
        fmt.timeZone = locationTimeZone
        return hour == 0 ? fmt.string(from: date) : "\(hour):00"
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: topBarHeight)
                    if showTide && !tideChartPoints.isEmpty && selectedLocation.id == "pda" {
                        tideCard
                    }
                    if tempChartMode == .continuous {
                        temperatureCard
                        cloudCard
                        humidityLineCard
                        precipitationCard
                        precipProbLineCard
                        windCard
                    } else {
                        temperatureCard
                        cloudCard
                        humidityCard
                        precipitationCard
                        precipProbCard
                        windMaxCard
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { v in
                        // Horizontal swipe switches chart mode; ignore mostly-vertical swipes
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tempChartMode = (tempChartMode == .continuous) ? .dailyMinMax : .continuous
                        }
                    }
            )
            topBar
        }
        .task(id: selectedLocation.id) { await loadWeatherForLocation() }
        .onAppear { displayedDays = defaultDays }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Verlauf · \(selectedLocation.name)")
                    .font(.headline)
                Spacer()
                Button {
                    showDayPicker = true
                } label: {
                    Text("\(displayedDays) Tage")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemFill))
                        .clipShape(Capsule())
                }
                .confirmationDialog("Anzahl Tage", isPresented: $showDayPicker, titleVisibility: .visible) {
                    ForEach([2, 3, 4, 5, 6, 7, 10, 14].filter { $0 <= maxDays }, id: \.self) { n in
                        Button("\(n) Tage") {
                            displayedDays = n
                            defaultDays = n
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Picker("Ort", selection: $selectedLocationId) {
                ForEach(forecastLocations) { loc in
                    Text(loc.shortName).tag(loc.id)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            HStack {
                if selectedLocation.id == "pda" {
                    Button {
                        withAnimation { showTide.toggle() }
                    } label: {
                        Label(
                            showTide ? "Gezeiten an" : "Gezeiten aus",
                            systemImage: showTide ? "water.waves" : "water.waves.slash"
                        )
                        .font(.caption)
                        .foregroundStyle(showTide ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Picker("", selection: $tempChartMode) {
                    Image(systemName: "waveform.path.ecg").tag(TempChartMode.continuous)
                    Image(systemName: "chart.dots.scatter").tag(TempChartMode.dailyMinMax)
                }
                .pickerStyle(.segmented)
                .frame(width: 88)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Color.clear.frame(height: 2)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var topBarHeight: CGFloat { 130 }

    // MARK: - Data loading

    private func loadWeatherForLocation() async {
        if selectedLocation.id == "pda" {
            verlaufHourly = viewModel.hourlyWeather.map { h in
                VerlaufHourlyPoint(time: h.time, temp: h.temp, humidity: h.humidity,
                                   cloudCover: h.cloudCover, precipProb: h.precipProb,
                                   windSpeed: h.windSpeed, windDirection: h.windDirection,
                                   precipitation: 0.0)
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude",      value: "\(selectedLocation.latitude)"),
            URLQueryItem(name: "longitude",     value: "\(selectedLocation.longitude)"),
            URLQueryItem(name: "hourly",        value: "temperature_2m,relative_humidity_2m,cloud_cover,precipitation_probability,precipitation,windspeed_10m,winddirection_10m"),
            URLQueryItem(name: "timezone",      value: selectedLocation.timezone),
            URLQueryItem(name: "forecast_days", value: "14"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }

        struct HResp: Decodable {
            struct H: Decodable {
                let time: [String]
                let temperature2m: [Double?]
                let relativeHumidity2m: [Int?]
                let cloudCover: [Int?]
                let precipitationProbability: [Int?]
                let precipitation: [Double?]
                let windspeed10m: [Double?]
                let winddirection10m: [Int?]
                enum CodingKeys: String, CodingKey {
                    case time
                    case temperature2m         = "temperature_2m"
                    case relativeHumidity2m    = "relative_humidity_2m"
                    case cloudCover            = "cloud_cover"
                    case precipitationProbability = "precipitation_probability"
                    case precipitation
                    case windspeed10m          = "windspeed_10m"
                    case winddirection10m      = "winddirection_10m"
                }
            }
            let hourly: H
        }
        guard let resp = try? JSONDecoder().decode(HResp.self, from: data) else { return }
        let tz = TimeZone(identifier: selectedLocation.timezone) ?? .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone = tz
        verlaufHourly = resp.hourly.time.enumerated().compactMap { idx, t -> VerlaufHourlyPoint? in
            guard let date = fmt.date(from: t),
                  let temp = resp.hourly.temperature2m[safe: idx] ?? nil else { return nil }
            return VerlaufHourlyPoint(
                time: date,
                temp: temp,
                humidity:      (resp.hourly.relativeHumidity2m[safe: idx]       ?? nil) ?? 0,
                cloudCover:    (resp.hourly.cloudCover[safe: idx]               ?? nil) ?? 0,
                precipProb:    (resp.hourly.precipitationProbability[safe: idx] ?? nil) ?? 0,
                windSpeed:     (resp.hourly.windspeed10m[safe: idx]             ?? nil) ?? 0,
                windDirection: (resp.hourly.winddirection10m[safe: idx]         ?? nil) ?? 0,
                precipitation: (resp.hourly.precipitation[safe: idx]            ?? nil) ?? 0.0
            )
        }
    }

    // MARK: - Daily stats for min/max chart

    private var dailyTempStats: [DailyTempStat] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byDay: [Date: [Double]] = [:]
        for h in hourlyWeather {
            let day = cal.startOfDay(for: h.time)
            byDay[day, default: []].append(h.temp)
        }
        return byDay.sorted { $0.key < $1.key }.compactMap { day, temps in
            guard !temps.isEmpty else { return nil }
            let noon = cal.date(byAdding: .hour, value: 12, to: day) ?? day
            let weekday = cal.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            return DailyTempStat(date: noon, dateStart: day,
                                  maxAir: temps.max()!, minAir: temps.min()!,
                                  isWeekend: isWeekend)
        }
    }

    private var dailyWaterTempStats: [(date: Date, temp: Double)] {
        guard selectedLocation.id == "pda" else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byDay: [Date: [Double]] = [:]
        for wt in marineWaterTemps {
            let day = cal.startOfDay(for: wt.time)
            byDay[day, default: []].append(wt.temp)
        }
        return byDay.sorted { $0.key < $1.key }.compactMap { day, temps in
            guard !temps.isEmpty else { return nil }
            let noon = cal.date(byAdding: .hour, value: 12, to: day) ?? day
            return (date: noon, temp: temps.reduce(0, +) / Double(temps.count))
        }
    }

    private func dailyDoubleStats(_ keyPath: KeyPath<VerlaufHourlyPoint, Double>) -> [DailyStatPoint] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: selectedLocation.timezone) ?? .current
        var byDay: [Date: [Double]] = [:]
        for h in hourlyWeather {
            let day = cal.startOfDay(for: h.time)
            byDay[day, default: []].append(h[keyPath: keyPath])
        }
        return byDay.sorted { $0.key < $1.key }.compactMap { day, vals -> DailyStatPoint? in
            // Skip partial days (< 12 data points) to avoid min == max artefacts
            guard vals.count >= 12 else { return nil }
            let noon = cal.date(byAdding: .hour, value: 12, to: day) ?? day
            let weekday = cal.component(.weekday, from: day)
            return DailyStatPoint(date: noon, dateStart: day,
                                   min: vals.min()!, max: vals.max()!,
                                   isWeekend: weekday == 1 || weekday == 7)
        }
    }

    private var dailyCloudStats:   [DailyStatPoint] { dailyDoubleStats(\.cloudDouble) }
    private var dailyHumidStats:   [DailyStatPoint] { dailyDoubleStats(\.humidDouble) }
    private var dailyPrecipPStats: [DailyStatPoint] { dailyDoubleStats(\.precipPDouble) }
    private var dailyWindMaxStats: [DailyStatPoint] { dailyDoubleStats(\.windSpeed) }

    // MARK: - Precipitation data

    /// Tages-Rohsummen
    private var dailyPrecipSum: [(date: Date, total: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byDay: [Date: Double] = [:]
        for h in hourlyWeather {
            let day = cal.startOfDay(for: h.time)
            byDay[day, default: 0] += h.precipitation
        }
        return byDay.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Tages-Rohsummen × max Regenwahrscheinlichkeit des Tages
    private var dailyPrecipMaxWeighted: [(date: Date, total: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byDayPrecip: [Date: Double] = [:]
        var byDayProb:   [Date: Double] = [:]
        for h in hourlyWeather {
            let day = cal.startOfDay(for: h.time)
            byDayPrecip[day, default: 0] += h.precipitation
            byDayProb[day] = max(byDayProb[day, default: 0], Double(h.precipProb))
        }
        return byDayPrecip.sorted { $0.key < $1.key }.map { day, sum in
            (day, sum * (byDayProb[day, default: 0] / 100.0))
        }
    }

    /// Tages-Rohsummen × mittlere Regenwahrscheinlichkeit des Tages
    private var dailyPrecipAvgWeighted: [(date: Date, total: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byDayPrecip: [Date: Double] = [:]
        var byDayProbSum: [Date: Double] = [:]
        var byDayCount:   [Date: Int]    = [:]
        for h in hourlyWeather {
            let day = cal.startOfDay(for: h.time)
            byDayPrecip[day, default: 0]   += h.precipitation
            byDayProbSum[day, default: 0]  += Double(h.precipProb)
            byDayCount[day, default: 0]    += 1
        }
        return byDayPrecip.sorted { $0.key < $1.key }.map { day, sum in
            let avgProb = byDayCount[day, default: 1] > 0
                ? byDayProbSum[day, default: 0] / Double(byDayCount[day, default: 1])
                : 0.0
            return (day, sum * (avgProb / 100.0))
        }
    }

    /// 6h-Rohsummen (4 Balken pro Tag: 0-6, 6-12, 12-18, 18-24)
    private var sixHourPrecipData: [(date: Date, total: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byBucket: [Date: Double] = [:]
        for h in hourlyWeather {
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: h.time)
            let bucketHour = ((comps.hour ?? 0) / 6) * 6
            var bc = comps; bc.hour = bucketHour; bc.minute = 0; bc.second = 0
            if let bd = cal.date(from: bc) { byBucket[bd, default: 0] += h.precipitation }
        }
        return byBucket.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// 6h-Rohsummen × max Regenwahrscheinlichkeit im 6h-Fenster
    private var sixHourPrecipMaxWeighted: [(date: Date, total: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byBucketPrecip: [Date: Double] = [:]
        var byBucketProb:   [Date: Double] = [:]
        for h in hourlyWeather {
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: h.time)
            let bucketHour = ((comps.hour ?? 0) / 6) * 6
            var bc = comps; bc.hour = bucketHour; bc.minute = 0; bc.second = 0
            if let bd = cal.date(from: bc) {
                byBucketPrecip[bd, default: 0] += h.precipitation
                byBucketProb[bd] = max(byBucketProb[bd, default: 0], Double(h.precipProb))
            }
        }
        return byBucketPrecip.sorted { $0.key < $1.key }.map { date, sum in
            (date, sum * (byBucketProb[date, default: 0] / 100.0))
        }
    }

    /// 6h-Rohsummen × mittlere Regenwahrscheinlichkeit im 6h-Fenster
    private var sixHourPrecipAvgWeighted: [(date: Date, total: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = locationTimeZone
        var byBucketPrecip:   [Date: Double] = [:]
        var byBucketProbSum:  [Date: Double] = [:]
        var byBucketCount:    [Date: Int]    = [:]
        for h in hourlyWeather {
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: h.time)
            let bucketHour = ((comps.hour ?? 0) / 6) * 6
            var bc = comps; bc.hour = bucketHour; bc.minute = 0; bc.second = 0
            if let bd = cal.date(from: bc) {
                byBucketPrecip[bd, default: 0]  += h.precipitation
                byBucketProbSum[bd, default: 0] += Double(h.precipProb)
                byBucketCount[bd, default: 0]   += 1
            }
        }
        return byBucketPrecip.sorted { $0.key < $1.key }.map { date, sum in
            let avgProb = byBucketCount[date, default: 1] > 0
                ? byBucketProbSum[date, default: 0] / Double(byBucketCount[date, default: 1])
                : 0.0
            return (date, sum * (avgProb / 100.0))
        }
    }

    // MARK: - Chart card helper

    @ViewBuilder
    private func precipAnnotation(_ total: Double) -> some View {
        Text(total >= 0.05 ? String(format: "%.1f", total) : " ")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.blue)
    }

    private func chartCard<Content: View>(title: String, tapHint: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if tapHint {
                    Image(systemName: "hand.tap")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            content()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Tide Chart

    private var tideCard: some View {
        let pts = tideChartPoints
        return chartCard(title: "Gezeiten") {
            Chart {
                ForEach(pts) { p in
                    AreaMark(
                        x: .value("Zeit", p.time),
                        yStart: .value("0", 0.0),
                        yEnd: .value("Höhe", viewModel.displayHeight(p.height))
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [.blue.opacity(0.25), .blue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(pts) { p in
                    LineMark(
                        x: .value("Zeit", p.time),
                        y: .value("Höhe", viewModel.displayHeight(p.height))
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
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
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 0.5)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(String(format: "%.1f", d)).font(.caption2)
                        }
                    }
                }
            }
            .chartYAxisLabel("m")
            .frame(height: 160)
        }
    }

    // MARK: - Temperature Chart

    private var temperatureCard: some View {
        chartCard(title: "Temperatur") {
            if tempChartMode == .continuous {
                continuousTempChart
            } else {
                dailyMinMaxTempChart
            }
            // Water temp label row (daily min/max mode, PdA only)
            if tempChartMode == .dailyMinMax, !dailyWaterTempStats.isEmpty {
                HStack(spacing: 0) {
                    // Align with chart plot area (y-axis labels take ~36pt on leading side)
                    Spacer().frame(width: 36)
                    ForEach(dailyWaterTempStats, id: \.date) { wt in
                        Text(String(format: "%.1f°", wt.temp))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.cyan)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 1)
            }
            HStack(spacing: 16) {
                legendItem(color: .red,  dash: false, label: "Luft max")
                legendItem(color: .blue, dash: false, label: "Luft min")
                if selectedLocation.id == "pda" {
                    legendItem(color: .teal, dash: false, label: "Wasser")
                }
            }
            .font(.caption2)
            .padding(.horizontal, 4)
        }
    }

    private var continuousTempChart: some View {
        let airPts: [VerlaufTempPoint] = hourlyWeather.map {
            VerlaufTempPoint(id: "a-\($0.id)", time: $0.time, value: $0.temp, series: "Luft")
        }
        let waterPts: [VerlaufTempPoint] = marineWaterTemps.enumerated().map { idx, wt in
            VerlaufTempPoint(id: "w-\(idx)", time: wt.time, value: wt.temp, series: "Wasser")
        }
        let allTemps = airPts.map(\.value) + waterPts.map(\.value)
        let minT = (allTemps.min() ?? 15) - 1
        let maxT = (allTemps.max() ?? 30) + 1

        return Chart {
            ForEach(airPts) { p in
                AreaMark(
                    x: .value("Zeit", p.time),
                    yStart: .value("Min", minT),
                    yEnd: .value("T", p.value)
                )
                .foregroundStyle(.linearGradient(
                    colors: [.red.opacity(0.15), .orange.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            }
            ForEach(airPts) { p in
                LineMark(x: .value("Zeit", p.time), y: .value("T", p.value))
                    .foregroundStyle(by: .value("Serie", p.series))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(waterPts) { p in
                LineMark(x: .value("Zeit", p.time), y: .value("T", p.value))
                    .foregroundStyle(by: .value("Serie", p.series))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartForegroundStyleScale(["Luft": Color.red, "Wasser": Color.teal])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { v in
                AxisGridLine()
                AxisValueLabel(centered: false) {
                    if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text("\(Int(d))°").font(.caption2) }
                }
            }
        }
        .chartYScale(domain: minT...maxT)
        .frame(height: 180)
    }

    private var dailyMinMaxTempChart: some View {
        let stats = dailyTempStats
        let allTemps = stats.flatMap { [$0.maxAir, $0.minAir] }
        let minY = (allTemps.min() ?? 15) - 2
        let maxY = (allTemps.max() ?? 35) + 4

        return Chart {
            ForEach(stats.filter(\.isWeekend)) { s in
                RectangleMark(
                    xStart: .value("Start", s.dateStart),
                    xEnd: .value("Ende", Calendar.current.date(byAdding: .day, value: 1, to: s.dateStart) ?? s.date),
                    yStart: .value("Bot", minY),
                    yEnd: .value("Top", maxY)
                )
                .foregroundStyle(Color.blue.opacity(0.07))
            }
            ForEach(stats) { s in
                LineMark(
                    x: .value("Tag", s.date),
                    y: .value("Temp", s.maxAir),
                    series: .value("Serie", "Max")
                )
                .foregroundStyle(Color.gray.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            ForEach(stats) { s in
                LineMark(
                    x: .value("Tag", s.date),
                    y: .value("Temp", s.minAir),
                    series: .value("Serie", "Min")
                )
                .foregroundStyle(Color.gray.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            ForEach(stats) { s in
                PointMark(x: .value("Tag", s.date), y: .value("Max", s.maxAir))
                    .foregroundStyle(.red)
                    .symbolSize(60)
                    .annotation(position: .top, spacing: 2) {
                        Text("\(Int(s.maxAir.rounded()))°")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                    }
            }
            ForEach(stats) { s in
                PointMark(x: .value("Tag", s.date), y: .value("Min", s.minAir))
                    .foregroundStyle(.blue)
                    .symbolSize(60)
                    .annotation(position: .bottom, spacing: 2) {
                        Text("\(Int(s.minAir.rounded()))°")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisValueLabel(
                    format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE")),
                    centered: true
                )
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text("\(Int(d))°").font(.caption2) }
                }
            }
        }
        .chartYScale(domain: minY...maxY)
        .frame(height: 200)
    }

    // MARK: - Atmosphere Chart

    private var atmosphereCard: some View {
        let atmoPoints: [VerlaufAtmoPoint] = hourlyWeather.flatMap { h in
            let ts = "\(h.time.timeIntervalSince1970)"
            return [
                VerlaufAtmoPoint(id: ts + "-f", time: h.time, value: h.humidity,   series: "Feuchte"),
                VerlaufAtmoPoint(id: ts + "-w", time: h.time, value: h.cloudCover, series: "Wolken"),
                VerlaufAtmoPoint(id: ts + "-r", time: h.time, value: h.precipProb, series: "Regen"),
            ]
        }

        return chartCard(title: "Atmosphäre") {
            Chart {
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
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Int.self) { Text("\(d)%").font(.caption2) }
                    }
                }
            }
            .frame(height: 180)

            HStack(spacing: 12) {
                legendItem(color: .teal,               dash: false, label: "Feuchte")
                legendItem(color: Color(.systemGray2), dash: false, label: "Bewölkung")
                legendItem(color: .blue,               dash: false, label: "Regen")
            }
            .font(.caption2)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Wind Chart

    private var windCard: some View {
        let windData = hourlyWeather
        let maxWind = max((windData.map(\.windSpeed).max() ?? 20) * 1.15, 5.0)

        return chartCard(title: "Wind") {
            Chart {
                ForEach(windData) { h in
                    AreaMark(
                        x: .value("Zeit", h.time),
                        yStart: .value("0", 0.0),
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
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
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
            .chartYScale(domain: 0...maxWind)
            .frame(height: 160)
        }
    }

    // MARK: - Daily min/max chart helper

    private func minMaxChart(
        stats: [DailyStatPoint],
        unit: String,
        minColor: Color,
        maxColor: Color,
        domainMin: Double = 0,
        domainMax: Double = 100,
        showMin: Bool = true
    ) -> some View {
        let minY = showMin ? (stats.map(\.min).min() ?? domainMin) - 2 : domainMin
        let maxY = (stats.map(\.max).max() ?? domainMax) + (showMin ? 4 : 2)

        return Chart {
            ForEach(stats.filter(\.isWeekend)) { s in
                RectangleMark(
                    xStart: .value("S", s.dateStart),
                    xEnd: .value("E", Calendar.current.date(byAdding: .day, value: 1, to: s.dateStart) ?? s.date),
                    yStart: .value("B", minY),
                    yEnd: .value("T", maxY)
                )
                .foregroundStyle(Color.blue.opacity(0.07))
            }
            ForEach(stats) { s in
                LineMark(x: .value("Tag", s.date), y: .value("V", s.max), series: .value("Serie", "Max"))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
            }
            if showMin {
                ForEach(stats) { s in
                    LineMark(x: .value("Tag", s.date), y: .value("V", s.min), series: .value("Serie", "Min"))
                        .foregroundStyle(Color.gray.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                }
            }
            ForEach(stats) { s in
                PointMark(x: .value("Tag", s.date), y: .value("V", s.max))
                    .foregroundStyle(maxColor)
                    .symbolSize(60)
                    .annotation(position: .top, spacing: 2) {
                        Text("\(Int(s.max.rounded()))\(unit)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(maxColor)
                    }
            }
            if showMin {
                ForEach(stats) { s in
                    PointMark(x: .value("Tag", s.date), y: .value("V", s.min))
                        .foregroundStyle(minColor)
                        .symbolSize(60)
                        .annotation(position: .bottom, spacing: 2) {
                            Text("\(Int(s.min.rounded()))\(unit)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(minColor)
                        }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisValueLabel(
                    format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE")),
                    centered: true
                )
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                if let d = v.as(Double.self) {
                    AxisValueLabel("\(Int(d))\(unit)")
                }
            }
        }
        .chartYScale(domain: minY...maxY)
        .frame(height: showMin ? 200 : 160)
    }

    // MARK: - Daily min/max cards

    private var cloudCard: some View {
        let cloudPts = hourlyWeather
        return chartCard(title: "Bewölkung") {
            Chart {
                ForEach(cloudPts) { h in
                    AreaMark(
                        x: .value("Zeit", h.time),
                        yStart: .value("0", 0.0),
                        yEnd: .value("%", h.cloudDouble)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [Color(.systemGray3).opacity(0.4), Color(.systemGray5).opacity(0.05)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(cloudPts) { h in
                    LineMark(x: .value("Zeit", h.time), y: .value("%", h.cloudDouble))
                        .foregroundStyle(Color(.systemGray2))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(
                    format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE")),
                    values: xAxisValues
                )
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine()
                    if let d = v.as(Int.self) { AxisValueLabel("\(d)%") }
                }
            }
            .frame(height: 140)
        }
    }

    private var humidityCard: some View {
        chartCard(title: "Luftfeuchtigkeit") {
            minMaxChart(stats: dailyHumidStats, unit: "%",
                        minColor: .teal.opacity(0.6), maxColor: .teal,
                        domainMax: 100)
            HStack(spacing: 12) {
                legendItem(color: .teal, dash: false, label: "Max")
                legendItem(color: .teal.opacity(0.6), dash: false, label: "Min")
            }
            .font(.caption2)
            .padding(.horizontal, 4)
        }
    }

    private var humidityLineCard: some View {
        chartCard(title: "Luftfeuchtigkeit") {
            Chart {
                ForEach(hourlyWeather) { h in
                    AreaMark(
                        x: .value("Zeit", h.time),
                        yStart: .value("0", 0.0),
                        yEnd: .value("%", h.humidDouble)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [Color.teal.opacity(0.3), Color.teal.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(hourlyWeather) { h in
                    LineMark(x: .value("Zeit", h.time), y: .value("%", h.humidDouble))
                        .foregroundStyle(.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine()
                    if let d = v.as(Int.self) { AxisValueLabel("\(d)%") }
                }
            }
            .frame(height: 140)
        }
    }

    private var precipProbLineCard: some View {
        chartCard(title: "Regenwahrscheinlichkeit") {
            Chart {
                ForEach(hourlyWeather) { h in
                    AreaMark(
                        x: .value("Zeit", h.time),
                        yStart: .value("0", 0),
                        yEnd: .value("%", h.precipProb)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(hourlyWeather) { h in
                    LineMark(x: .value("Zeit", h.time), y: .value("%", h.precipProb))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine()
                    if let d = v.as(Int.self) { AxisValueLabel("\(d)%") }
                }
            }
            .frame(height: 140)
        }
    }

    @ViewBuilder
    private var precipitationCard: some View {
        if tempChartMode == .dailyMinMax {
            precipitationDailyCard
        } else {
            precipitationSixHourCard
        }
    }

    private var precipitationDailyCard: some View {
        let rawData: [(date: Date, total: Double)]
        let title: String
        switch precipMode {
        case 1:  rawData = dailyPrecipMaxWeighted; title = "Niederschlag × max. W'keit"
        case 2:  rawData = dailyPrecipAvgWeighted; title = "Niederschlag × mittlere W'keit"
        default: rawData = dailyPrecipSum;          title = "Niederschlag"
        }
        let maxVal = max((rawData.map(\.total).max() ?? 5) * 1.2, 0.1)
        return chartCard(title: title, tapHint: true) {
            Chart {
                ForEach(rawData, id: \.date) { d in
                    // unit: .day → bar spans full calendar day, auto-grounded at 0
                    BarMark(x: .value("Tag", d.date, unit: .day),
                            y: .value("mm", d.total))
                        .foregroundStyle(Color.blue.opacity(0.75))
                        .annotation(position: .top, spacing: 2) { precipAnnotation(d.total) }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisValueLabel(
                        format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE")),
                        centered: true
                    )
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine()
                    if let d = v.as(Double.self) {
                        AxisValueLabel(String(format: "%.1fmm", d))
                    }
                }
            }
            .chartYScale(domain: 0...maxVal)
            .frame(height: 140)
            .contentShape(Rectangle())
            .onTapGesture { precipMode = (precipMode + 1) % 3 }
        }
    }

    // Separate function breaks the compiler's generic inference problem
    private func sixHourChart(bars: [SixHourBar], maxVal: Double) -> some View {
        Chart {
            ForEach(bars) { bar in
                RectangleMark(xStart: .value("S", bar.start),
                              xEnd:   .value("E", bar.end),
                              yStart: .value("0", 0.0),
                              yEnd:   .value("V", bar.total))
                    .foregroundStyle(Color.blue.opacity(0.75))
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
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                if let d = v.as(Double.self) {
                    AxisValueLabel(String(format: "%.1fmm", d))
                }
            }
        }
        .chartYScale(domain: 0...maxVal)
        .frame(height: 140)
    }

    private var precipitationSixHourCard: some View {
        let raw: [(date: Date, total: Double)]
        let title: String
        switch precipMode {
        case 1:  raw = sixHourPrecipMaxWeighted; title = "Niederschlag × max. W'keit"
        case 2:  raw = sixHourPrecipAvgWeighted; title = "Niederschlag × mittlere W'keit"
        default: raw = sixHourPrecipData;         title = "Niederschlag"
        }
        let bars   = raw.map { SixHourBar(start: $0.date,
                                          end:   $0.date.addingTimeInterval(6 * 3600),
                                          total: $0.total) }
        let maxVal = max((raw.map(\.total).max() ?? 5) * 1.2, 0.1)
        return chartCard(title: title, tapHint: true) {
            sixHourChart(bars: bars, maxVal: maxVal)
                .contentShape(Rectangle())
                .onTapGesture { precipMode = (precipMode + 1) % 3 }
        }
    }

    private var precipProbCard: some View {
        chartCard(title: "Regenwahrscheinlichkeit") {
            minMaxChart(stats: dailyPrecipPStats, unit: "%",
                        minColor: .blue.opacity(0.5), maxColor: .blue,
                        domainMax: 100, showMin: false)
        }
    }

    private var windMaxCard: some View {
        let stats = dailyWindMaxStats
        let maxWind = (stats.map(\.max).max() ?? 30) + 8
        return chartCard(title: "Wind (Maximum)") {
            Chart {
                ForEach(stats.filter(\.isWeekend)) { s in
                    RectangleMark(
                        xStart: .value("S", s.dateStart),
                        xEnd: .value("E", Calendar.current.date(byAdding: .day, value: 1, to: s.dateStart) ?? s.date),
                        yStart: .value("B", 0.0),
                        yEnd: .value("T", maxWind)
                    )
                    .foregroundStyle(Color.blue.opacity(0.07))
                }
                // Connecting line
                ForEach(stats) { s in
                    LineMark(
                        x: .value("Tag", s.date),
                        y: .value("km/h", s.max),
                        series: .value("Serie", "W")
                    )
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                // Dots + labels
                ForEach(stats) { s in
                    PointMark(x: .value("Tag", s.date), y: .value("km/h", s.max))
                        .foregroundStyle(.teal)
                        .symbolSize(70)
                        .annotation(position: .top, spacing: 2) {
                            Text("\(Int(s.max.rounded()))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.teal)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(
                    format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE")),
                    values: .stride(by: .day, count: 1)
                )
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine()
                    if let d = v.as(Double.self) {
                        AxisValueLabel("\(Int(d))")
                    }
                }
            }
            .chartYScale(domain: 0...maxWind)
            .frame(height: 160)
        }
    }

    // MARK: - Wind arrow

    private func windArrow(_ degrees: Int) -> String {
        let arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
        return arrows[Int((Double(degrees) + 22.5) / 45.0) % 8]
    }

    // MARK: - Legend helper

    private func legendItem(color: Color, dash: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            if dash {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(color).frame(width: 4, height: 2)
                        Rectangle().fill(.clear).frame(width: 2, height: 2)
                    }
                }
                .frame(width: 18, height: 2)
            } else {
                Rectangle().fill(color).frame(width: 18, height: 2)
            }
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Private supporting types

private struct VerlaufHourlyPoint: Identifiable {
    let id = UUID()
    let time: Date
    let temp: Double
    let humidity: Int
    let cloudCover: Int
    let precipProb: Int
    let windSpeed: Double
    let windDirection: Int
    let precipitation: Double

    var cloudDouble:   Double { Double(cloudCover) }
    var humidDouble:   Double { Double(humidity) }
    var precipPDouble: Double { Double(precipProb) }
}

private struct VerlaufTempPoint: Identifiable {
    let id: String
    let time: Date
    let value: Double
    let series: String
}

private struct VerlaufAtmoPoint: Identifiable {
    let id: String
    let time: Date
    let value: Int
    let series: String
}

private struct DailyTempStat: Identifiable {
    let id = UUID()
    let date: Date
    let dateStart: Date
    let maxAir: Double
    let minAir: Double
    let isWeekend: Bool
}

private struct DailyStatPoint: Identifiable {
    let id = UUID()
    let date: Date
    let dateStart: Date
    let min: Double
    let max: Double
    let isWeekend: Bool
}

private struct SixHourBar: Identifiable {
    let id    = UUID()
    let start : Date
    let end   : Date
    let total : Double
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
