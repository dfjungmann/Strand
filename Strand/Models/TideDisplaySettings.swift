import Foundation

/// Anzeige-Einstellungen (lokal; Watch erhält Werte per WatchConnectivity vom iPhone).
enum TideDisplaySettings {
    #if os(watchOS)
    /// Standard-Referenz Arinaga/Pasito Blanco, falls iPhone noch nicht synchronisiert hat.
    private static let defaultReferenceOffsetCm = 120
    #endif

    static var timeOffsetMinutes: Int {
        UserDefaults.standard.object(forKey: TideSettingsKeys.timeOffsetMinutes) as? Int ?? 0
    }

    static var tideReferenceOffsetCm: Int {
        if let v = UserDefaults.standard.object(forKey: TideSettingsKeys.tideReferenceOffsetCm) as? Int {
            return v
        }
        #if os(watchOS)
        return defaultReferenceOffsetCm
        #else
        return 0
        #endif
    }

    static func displayHeight(_ rawHeight: Double) -> Double {
        rawHeight - Double(tideReferenceOffsetCm) / 100.0
    }

    static func displayHeightValueFormatted(_ rawHeight: Double) -> String {
        String(format: "%.2f", displayHeight(rawHeight))
    }
}
