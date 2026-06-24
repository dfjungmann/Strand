import Foundation
import Observation

@Observable
final class TideViewModel {

    // MARK: - Constants

    static let totalDays = 7          // always fetch & show 7 days
    static let chartDayOptions = Array(1...7)

    // MARK: - Settings (persisted)

    var chartDays: Int {
        didSet { UserDefaults.standard.set(chartDays, forKey: "chartDays") }
    }
    var timeOffsetMinutes: Int {
        didSet { UserDefaults.standard.set(timeOffsetMinutes, forKey: "timeOffsetMinutes") }
    }
    var beachWalkThreshold: Double {
        didSet { UserDefaults.standard.set(beachWalkThreshold, forKey: "beachWalkThreshold") }
    }

    // MARK: - State

    var tideDays: [TideDay] = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?
    var cachedDayCount: Int = 0

    // MARK: - Init

    init() {
        let storedChart = UserDefaults.standard.integer(forKey: "chartDays")
        chartDays = (1...7).contains(storedChart) ? storedChart : 3

        let storedOffset = UserDefaults.standard.object(forKey: "timeOffsetMinutes") as? Int
        timeOffsetMinutes = storedOffset ?? -15

        let storedThreshold = UserDefaults.standard.object(forKey: "beachWalkThreshold") as? Double
        beachWalkThreshold = storedThreshold ?? 0.6
    }

    // MARK: - Data Loading

    @MainActor
    func loadTides() async {
        isLoading = true
        errorMessage = nil
        do {
            var days = try await TideService.shared.fetchTides(
                forDays: Self.totalDays,
                timeOffsetMinutes: timeOffsetMinutes
            )
            days = applyBeachWalkPrediction(to: days)
            tideDays = days
            lastUpdated = Date()
            cachedDayCount = await TideCache.shared.cachedDayCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func reload() async {
        tideDays = []
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
                e.isBeachWalkPossible = (event.type == .lowTide && event.height <= beachWalkThreshold)
                return e
            }
            return updated
        }
    }

    // MARK: - Chart Data

    /// Days shown in chart (first `chartDays` of the loaded 7 days)
    var chartDisplayDays: [TideDay] {
        Array(tideDays.prefix(chartDays))
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
