import Foundation

/// Sichert und stellt App-Einstellungen wieder her (überlebt App-Deinstallation).
enum SettingsBackup {
    static let fileName = "Strand-Einstellungen.json"
    static let version = 1

    /// Alle persistierten UserDefaults-Keys der App.
    private static let keys: [String] = [
        "chartDays", "chartStartOffset", "timeOffsetMinutes",
        "beachWalkThresholdSafe", "beachWalkThresholdLikely", "beachWalkDeepCm",
        "tide_reference_offset_cm",
        "showAstronomy", "showWeather", "showWaves", "table_show_wind", "tableFontSize",
        "verlauf_default_days", "shared_location_id",
        "notif_enabled", "notif_window_start", "notif_window_end",
        "notif_content_start", "notif_content_end",
        "notif_daily_enabled", "notif_daily_hour", "notif_daily_minute",
        "notif_daily_low_today", "notif_daily_walk_today",
        "notif_daily_low_tomorrow", "notif_daily_walk_tomorrow",
        "notif_daily_low2_tomorrow", "notif_daily_walk2_tomorrow",
        "notif_daily_water_temp", "notif_daily_moon",
        "notif_prewalk_enabled", "notif_prewalk_hours", "notif_at_tide_enabled",
        "owm_api_key", "openai_api_key",
        "radar_intensity", "radar_default_location",
    ]

    struct Payload: Codable {
        let version: Int
        let exportedAt: Date
        let values: [String: BackupValue]
    }

    enum BackupValue: Codable, Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        init(from value: Any) {
            switch value {
            case let v as String: self = .string(v)
            case let v as Int: self = .int(v)
            case let v as Double: self = .double(v)
            case let v as Bool: self = .bool(v)
            case let v as Float: self = .double(Double(v))
            default: self = .string(String(describing: value))
            }
        }

        func apply(to defaults: UserDefaults, key: String) {
            switch self {
            case .string(let v): defaults.set(v, forKey: key)
            case .int(let v): defaults.set(v, forKey: key)
            case .double(let v): defaults.set(v, forKey: key)
            case .bool(let v): defaults.set(v, forKey: key)
            }
        }
    }

    static func exportData() throws -> Data {
        let defaults = UserDefaults.standard
        var values: [String: BackupValue] = [:]
        for key in keys {
            guard let raw = defaults.object(forKey: key) else { continue }
            values[key] = BackupValue(from: raw)
        }
        let payload = Payload(version: version, exportedAt: Date(), values: values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func importData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.version <= version else {
            throw BackupError.unsupportedVersion(payload.version)
        }
        let defaults = UserDefaults.standard
        for (key, value) in payload.values where keys.contains(key) {
            value.apply(to: defaults, key: key)
        }
        return payload.values.count
    }

    enum BackupError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "Backup-Version \(v) wird nicht unterstützt."
            }
        }
    }
}
