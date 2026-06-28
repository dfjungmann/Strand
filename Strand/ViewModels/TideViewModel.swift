import Foundation
import Observation

@Observable
final class TideViewModel {

    // MARK: - Constants

    static let totalDays = 10         // always fetch & show 10 days
    static let chartDayOptions: [(days: Int, label: String)] = [
        (1, "1 Tag"), (2, "2 Tage"), (3, "3 Tage"), (7, "1 Woche")
    ]
    static let chartStartOptions: [(offset: Int, label: String)] = [
        (0, "Heute"), (1, "Morgen"), (2, "Übermorgen")
    ]

    // MARK: - Settings (persisted)

    var chartDays: Int {
        didSet { UserDefaults.standard.set(chartDays, forKey: "chartDays") }
    }
    var chartStartOffset: Int {
        didSet { UserDefaults.standard.set(chartStartOffset, forKey: "chartStartOffset") }
    }
    var timeOffsetMinutes: Int {
        didSet { UserDefaults.standard.set(timeOffsetMinutes, forKey: "timeOffsetMinutes") }
    }
    /// Sichere Grenze – Markierung grün
    var beachWalkThresholdSafe: Double {
        didSet { UserDefaults.standard.set(beachWalkThresholdSafe, forKey: "beachWalkThresholdSafe") }
    }
    /// Wahrscheinliche Grenze – Markierung gelb (muss >= safe sein)
    var beachWalkThresholdLikely: Double {
        didSet { UserDefaults.standard.set(beachWalkThresholdLikely, forKey: "beachWalkThresholdLikely") }
    }
    /// Offset in cm subtrahiert von Rohwert (SKN) für die Anzeige; 0 = Seekartennull, ~120 = Mittelwasser
    var tideReferenceOffsetCm: Int {
        didSet { UserDefaults.standard.set(tideReferenceOffsetCm, forKey: "tide_reference_offset_cm") }
    }

    // MARK: - State

    var tideDays: [TideDay] = []
    var weatherDays: [WeatherDay] = []
    var hourlyWeather: [HourlyWeather] = []
    var hourlyMarine: [HourlyMarine] = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?
    var cachedDayCount: Int = 0

    // MARK: - Init

    init() {
        let storedChart = UserDefaults.standard.integer(forKey: "chartDays")
        chartDays = (1...7).contains(storedChart) ? storedChart : 3

        let storedOffset = UserDefaults.standard.integer(forKey: "chartStartOffset")
        chartStartOffset = (0...2).contains(storedOffset) ? storedOffset : 0

        let storedTimeOffset = UserDefaults.standard.object(forKey: "timeOffsetMinutes") as? Int
        timeOffsetMinutes = storedTimeOffset ?? 0

        let storedSafe = UserDefaults.standard.object(forKey: "beachWalkThresholdSafe") as? Double
        beachWalkThresholdSafe = storedSafe ?? 0.55

        let storedLikely = UserDefaults.standard.object(forKey: "beachWalkThresholdLikely") as? Double
        beachWalkThresholdLikely = storedLikely ?? 0.65

        let storedRefOffset = UserDefaults.standard.object(forKey: "tide_reference_offset_cm") as? Int
        tideReferenceOffsetCm = storedRefOffset ?? 0
    }

    // MARK: - Data Loading

    @MainActor
    func loadTides() async {
        isLoading = true
        errorMessage = nil
        async let tideFetch = TideService.shared.fetchTides(
            forDays: Self.totalDays,
            timeOffsetMinutes: timeOffsetMinutes
        )
        async let weatherFetch = WeatherService.shared.fetchWeather(days: Self.totalDays)
        async let marineFetch = MarineService.shared.fetchMarine(days: Self.totalDays)

        do {
            var days = try await tideFetch
            days = applyBeachWalkPrediction(to: days)
            tideDays = days
            cachedDayCount = await TideCache.shared.cachedDayCount
        } catch {
            errorMessage = error.localizedDescription
        }
        // Weather failures are non-fatal
        if let wx = try? await weatherFetch {
            weatherDays = wx.days
            hourlyWeather = wx.hourly
        }
        // Marine failures are non-fatal
        if let marine = try? await marineFetch {
            hourlyMarine = marine
        }
        lastUpdated = Date()
        isLoading = false
        Task { @MainActor in
            await NotificationManager.shared.reschedule(viewModel: self)
        }
    }

    @MainActor
    func reload() async {
        tideDays = []
        // weatherDays and hourlyWeather are intentionally NOT cleared here.
        // Keeping old weather data visible during a reload prevents the table from
        // going blank if the network fetch fails (e.g. triggered by an accidental
        // pull-to-refresh while the List re-layouts after a font-size change).
        // loadTides() will overwrite weather data if the fresh fetch succeeds.
        await loadTides()
    }

    @MainActor
    func clearCache() async {
        await TideCache.shared.clearAll()
        cachedDayCount = 0
        await reload()
    }

    // MARK: - Beach Walk

    private func applyBeachWalkPrediction(to days: [TideDay]) -> [TideDay] {
        days.map { day in
            var updated = day
            updated.events = day.events.map { event in
                var e = event
                guard event.type == .lowTide else {
                    e.beachWalkStatus = .none
                    return e
                }
                if event.height <= beachWalkThresholdSafe {
                    e.beachWalkStatus = .safe
                } else if event.height <= beachWalkThresholdLikely {
                    e.beachWalkStatus = .likely
                } else {
                    e.beachWalkStatus = .none
                }
                return e
            }
            return updated
        }
    }

    /// Convenience: old single threshold, kept for BeachWalkView gauge
    var beachWalkThreshold: Double { beachWalkThresholdSafe }

    // MARK: - Weather Lookup

    /// Returns hourly weather data for a window of `dayCount` days starting at `startDate`
    func hourlyWeather(from startDate: Date, dayCount: Int) -> [HourlyWeather] {
        let end = Calendar.current.date(byAdding: .day, value: dayCount, to: startDate)!
        return hourlyWeather.filter { $0.time >= startDate && $0.time < end }
    }

    func weather(for date: Date) -> WeatherDay? {
        let canary = TideService.canaryIslandsTimeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = canary
        let target = cal.startOfDay(for: date)
        return weatherDays.first { cal.startOfDay(for: $0.date) == target }
    }

    // MARK: - Marine Lookup

    /// Returns hourly marine data for a window of `dayCount` days starting at `startDate`
    func marineData(from startDate: Date, dayCount: Int) -> [HourlyMarine] {
        let end = Calendar.current.date(byAdding: .day, value: dayCount, to: startDate)!
        return hourlyMarine.filter { $0.time >= startDate && $0.time < end }
    }

    /// Nearest hourly wave height for a given point in time
    func waveHeight(at date: Date) -> Double? {
        hourlyMarine.min(by: {
            abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date))
        })?.waveHeight
    }

    /// Maximum wind speed (km/h) for the calendar day of `date`
    func maxWindSpeed(for date: Date) -> Double? {
        let canary = TideService.canaryIslandsTimeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = canary
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        let speeds = hourlyWeather
            .filter { $0.time >= startOfDay && $0.time < endOfDay }
            .map(\.windSpeed)
        guard !speeds.isEmpty else { return nil }
        return speeds.max()
    }

    /// Mean water temperature for the calendar day of `date`
    func meanWaterTemp(for date: Date) -> Double? {
        let canary = TideService.canaryIslandsTimeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = canary
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        let temps = hourlyMarine
            .filter { $0.time >= startOfDay && $0.time < endOfDay }
            .compactMap(\.waterTemp)
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    // MARK: - Chart Data

    /// Days shown in chart: `chartDays` days starting from `chartStartOffset`
    var chartDisplayDays: [TideDay] {
        let start = min(chartStartOffset, max(0, tideDays.count - 1))
        return Array(tideDays.dropFirst(start).prefix(chartDays))
    }

    /// Continuous sinusoidal interpolation across multiple days for the chart
    func chartPoints(for days: [TideDay], resolution: Int = 200) -> [TideChartPoint] {
        let events = days.flatMap { $0.events }.sorted { $0.adjustedTime < $1.adjustedTime }
        guard events.count >= 2 else { return [] }

        var points: [TideChartPoint] = []
        for i in 0..<events.count - 1 {
            let start = events[i]
            let end = events[i + 1]
            let duration = end.adjustedTime.timeIntervalSince(start.adjustedTime)
            let steps = max(8, Int(duration / 60 / 5))  // 1 point per 5 minutes

            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let smooth = (1 - cos(fraction * .pi)) / 2
                let height = start.height + (end.height - start.height) * smooth
                let time = start.adjustedTime.addingTimeInterval(duration * fraction)
                points.append(TideChartPoint(time: time, height: height))
            }
        }
        return points
    }

    /// Day boundary times for vertical separators in multi-day chart
    func dayBoundaries(for days: [TideDay]) -> [Date] {
        guard days.count > 1 else { return [] }
        return days.dropFirst().compactMap { day in
            Calendar.current.startOfDay(for: day.date)
        }
    }

    // MARK: - Display Height

    /// Verschiebt Rohwert (Seekartennull-Referenz) um den konfigurierten Offset für die Anzeige.
    func displayHeight(_ rawHeight: Double) -> Double {
        rawHeight - Double(tideReferenceOffsetCm) / 100.0
    }

    func displayHeightFormatted(_ rawHeight: Double) -> String {
        String(format: "%.2f m", displayHeight(rawHeight))
    }

    // MARK: - Formatting

    func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = TideService.canaryIslandsTimeZone
        return f.string(from: date)
    }

    func formatDayHeader(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d. MMMM"
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TideService.canaryIslandsTimeZone
        return f.string(from: date)
    }

    func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "E d.M."
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TideService.canaryIslandsTimeZone
        return f.string(from: date)
    }

    var lastUpdatedFormatted: String {
        guard let date = lastUpdated else { return "–" }
        let f = DateFormatter()
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
