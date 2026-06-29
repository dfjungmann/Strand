import Foundation
import Observation

@MainActor
@Observable
final class WatchTideViewModel {
    var tideDays: [TideDay] = []
    var isLoading = false
    var errorMessage: String?

    var allEvents: [TideEvent] {
        tideDays.flatMap(\.events).sorted { $0.adjustedTime < $1.adjustedTime }
    }

    func loadTides() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let days = TideBeachWalk.apply(to: try await TideService.shared.fetchTides(
                forDays: 4,
                timeOffsetMinutes: TideDisplaySettings.timeOffsetMinutes
            ))
            tideDays = days
            TideComplicationStore.saveEvents(allEvents)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
