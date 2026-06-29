import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Gezeitendaten + Einstellungen für die Watch-Komplikation.
enum TideComplicationStore {
    private static let appGroupID = "group.de.dietmar.strand.47D76MD2KB"
    private static let fileName = "complication_payload_v1.json"
    private static let localKey = "complication_payload_local_v1"

    private static var payloadFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func saveEvents(_ events: [TideEvent]) {
        let payload = TideComplicationPayload(
            events: events,
            tideReferenceOffsetCm: TideDisplaySettings.tideReferenceOffsetCm,
            timeOffsetMinutes: TideDisplaySettings.timeOffsetMinutes
        )
        writePayload(payload)
        reloadTimelines()
    }

    /// Events + Einstellungen für Anzeige (Watch-App und Komplikation).
    static func loadEventsForDisplay() -> [TideEvent] {
        guard let payload = loadPayload() else { return [] }
        applySettings(from: payload)
        return payload.events
    }

    static func loadEventsOrFetch() async -> [TideEvent] {
        let cached = loadEventsForDisplay()
        if !cached.isEmpty { return cached }

        do {
            var days = try await TideService.shared.fetchTides(
                forDays: 2,
                timeOffsetMinutes: TideDisplaySettings.timeOffsetMinutes
            )
            days = TideBeachWalk.apply(to: days)
            let events = days.flatMap(\.events).sorted { $0.adjustedTime < $1.adjustedTime }
            saveEvents(events)
            return events
        } catch {
            return loadEventsForDisplay()
        }
    }

    static func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - Payload I/O

    private static func loadPayload() -> TideComplicationPayload? {
        if let url = payloadFileURL,
           let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(TideComplicationPayload.self, from: data) {
            return payload
        }
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let payload = try? JSONDecoder().decode(TideComplicationPayload.self, from: data) else {
            return nil
        }
        return payload
    }

    private static func writePayload(_ payload: TideComplicationPayload) {
        applySettings(from: payload)
        if let url = payloadFileURL,
           let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    private static func applySettings(from payload: TideComplicationPayload) {
        let d = UserDefaults.standard
        d.set(payload.tideReferenceOffsetCm, forKey: TideSettingsKeys.tideReferenceOffsetCm)
        d.set(payload.timeOffsetMinutes, forKey: TideSettingsKeys.timeOffsetMinutes)
    }
}

private struct TideComplicationPayload: Codable {
    let events: [TideEvent]
    let tideReferenceOffsetCm: Int
    let timeOffsetMinutes: Int
}
