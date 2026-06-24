import Foundation
import Observation

@Observable
final class TideViewModel {

    // MARK: - Settings (persisted)

    var selectedDays: Int {
        didSet { UserDefaults.standard.set(selectedDays, forKey: "selectedDays") }
    }
    var timeOffsetMinutes: Int {
        didSet { UserDefaults.standard.set(timeOffsetMinutes, forKey: "timeOffsetMinutes") }
    }
    var beachWalkThreshold: Double {
        didSet { UserDefaults.standard.set(beachWalkThreshold, forKey: "beachWalkThreshold") }
    }

    static let availableDays = [2, 3, 4, 5, 7]

    // MARK: - State

    var tideDays: [TideDay] = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    // MARK: - Init

    init() {
        let storedDays = UserDefaults.standard.integer(forKey: "selectedDays")
        selectedDays = Self.availableDays.contains(storedDays) ? storedDays : 3

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
                forDays: selectedDays,
                timeOffsetMinutes: timeOffsetMinutes
            )
            days = applyBeachWalkPrediction(to: days)
            tideDays = days
            lastUpdated = Date()
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

    // MARK: - Beach Walk Logic

    private func applyBeachWalkPrediction(to days: [TideDay]) -> [TideDay] {
        days.map { day in
            var updated = day
            updated.events = day.events.map { event in
                var e = event
                // Beach walk possible when LOW TIDE height is below threshold
                e.isBeachWalkPossible = (event.type == .lowTide && event.height <= beachWalkThreshold)
                return e
            }
            return updated
        }
    }

    // MARK: - Chart Data

    /// Generates a smooth sinusoidal interpolation between tide events for chart display
    func chartPoints(for day: TideDay, resolution: Int = 120) -> [TideChartPoint] {
        let events = day.events
        guard events.count >= 2 else { return [] }

        var points: [TideChartPoint] = []

        for i in 0..<events.count - 1 {
            let start = events[i]
            let end = events[i + 1]
            let duration = end.adjustedTime.timeIntervalSince(start.adjustedTime)
            let steps = max(1, Int(duration / 60 / (24 * 60 / Double(resolution))))

            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                // Cosine interpolation for smooth wave
                let smoothFraction = (1 - cos(fraction * .pi)) / 2
                let height = start.height + (end.height - start.height) * smoothFraction
                let time = start.adjustedTime.addingTimeInterval(duration * fraction)
                points.append(TideChartPoint(time: time, height: height))
            }
        }
        return points
    }

    // MARK: - Formatting Helpers

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TideService.canaryIslandsTimeZone
        return formatter.string(from: date)
    }

    func formatDayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d. MMMM"
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TideService.canaryIslandsTimeZone
        return formatter.string(from: date)
    }

    func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E d.M."
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TideService.canaryIslandsTimeZone
        return formatter.string(from: date)
    }

    var lastUpdatedFormatted: String {
        guard let date = lastUpdated else { return "–" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
