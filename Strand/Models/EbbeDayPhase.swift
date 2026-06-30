import Foundation

/// Tageszeit-Lage einer Ebbe (Vorschau in der Gezeiten-Uhr).
enum EbbeDayPhase: String {
    case beforeSunrise = "Vor Sonnenaufgang"
    case morning = "Vormittag"
    case afternoon = "Nachmittag"
    case evening = "Abend"
    case afterSunset = "Nach Sonnenuntergang"

    static let eveningLeadTime: TimeInterval = 1.5 * 3600

    static func classify(ebbeTime: Date, astronomy: AstronomyData) -> EbbeDayPhase {
        guard let sunrise = astronomy.sunrise, let sunset = astronomy.sunset else {
            return classifyByHour(ebbeTime)
        }

        if ebbeTime < sunrise { return .beforeSunrise }
        if ebbeTime >= sunset { return .afterSunset }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let dayStart = cal.startOfDay(for: ebbeTime)
        let noon = cal.date(byAdding: .hour, value: 12, to: dayStart) ?? ebbeTime
        let eveningStart = sunset.addingTimeInterval(-eveningLeadTime)

        if ebbeTime < noon { return .morning }
        if ebbeTime < eveningStart { return .afternoon }
        return .evening
    }

    /// Sonnen-/Mondposition auf dem Halbkreis: x,y relativ 0…1 (Horizont bei y≈0.72).
    static func celestialFraction(
        ebbeTime: Date,
        phase: EbbeDayPhase,
        astronomy: AstronomyData
    ) -> (x: Double, y: Double) {
        guard let sunrise = astronomy.sunrise, let sunset = astronomy.sunset else {
            return fallbackPosition(for: phase)
        }

        switch phase {
        case .beforeSunrise:
            return (0.18, 0.52)
        case .afterSunset:
            return (0.82, 0.52)
        case .morning, .afternoon, .evening:
            let span = sunset.timeIntervalSince(sunrise)
            guard span > 0 else { return (0.5, 0.35) }
            let t = min(1, max(0, ebbeTime.timeIntervalSince(sunrise) / span))
            let angle = Double.pi * (1 - t)
            let x = 0.5 + 0.38 * cos(angle)
            let y = 0.72 - 0.34 * sin(angle)
            return (x, y)
        }
    }

    private static func classifyByHour(_ date: Date) -> EbbeDayPhase {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let hour = cal.component(.hour, from: date)
        switch hour {
        case 0..<6: return .beforeSunrise
        case 6..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<20: return .evening
        default: return .afterSunset
        }
    }

    private static func fallbackPosition(for phase: EbbeDayPhase) -> (x: Double, y: Double) {
        switch phase {
        case .beforeSunrise: return (0.18, 0.52)
        case .morning: return (0.28, 0.48)
        case .afternoon: return (0.52, 0.38)
        case .evening: return (0.72, 0.48)
        case .afterSunset: return (0.82, 0.52)
        }
    }
}
