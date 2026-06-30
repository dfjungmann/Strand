import Foundation

/// Tageszeit-Lage einer Ebbe (Vorschau in der Gezeiten-Uhr).
enum EbbeDayPhase: String {
    case beforeSunrise = "Vor Sonnenaufgang"
    case morning = "Vormittag"
    case afternoon = "Nachmittag"
    case evening = "Abend"
    case afterSunset = "Nach Sonnenuntergang"

    var isNight: Bool {
        self == .beforeSunrise || self == .afterSunset
    }

    static let eveningLeadTime: TimeInterval = 1.5 * 3600

    /// Wie Tab „Tabelle“: Astronomie zum Gezeitentag.
    static func astronomy(for referenceDay: Date) -> AstronomyData {
        AstronomyService.data(for: referenceDay)
    }

    static func classify(ebbeTime: Date, referenceDay: Date) -> EbbeDayPhase {
        let astro = astronomy(for: referenceDay)
        guard let sunrise = astro.sunrise, let sunset = astro.sunset else {
            return classifyByHour(ebbeTime)
        }

        if ebbeTime < sunrise { return .beforeSunrise }
        if ebbeTime >= sunset { return .afterSunset }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let dayStart = cal.startOfDay(for: referenceDay)
        let noon = cal.date(byAdding: .hour, value: 12, to: dayStart) ?? ebbeTime
        let eveningStart = sunset.addingTimeInterval(-eveningLeadTime)

        if ebbeTime < noon { return .morning }
        if ebbeTime < eveningStart { return .afternoon }
        return .evening
    }

    /// Sonnenposition auf dem Tages-/Nacht-Halbkreis: x,y relativ 0…1 (Horizont bei y=0.5).
    static let arcCenterFraction = 0.5
    static let sunRadiusFraction = 0.065
    static let arcRadiusFraction = 0.5 - sunRadiusFraction - 0.025

    static func celestialFraction(ebbeTime: Date, phase: EbbeDayPhase, referenceDay: Date) -> (x: Double, y: Double) {
        let today = astronomy(for: referenceDay)

        switch phase {
        case .beforeSunrise, .afterSunset:
            guard let window = nightWindow(ebbeTime: ebbeTime, referenceDay: referenceDay) else {
                return fallbackPosition(for: phase, ebbeTime: ebbeTime)
            }
            let span = window.end.timeIntervalSince(window.start)
            guard span > 0 else { return fallbackPosition(for: phase, ebbeTime: ebbeTime) }
            let progress = min(1, max(0, ebbeTime.timeIntervalSince(window.start) / span))
            // Unterer Halbkreis: Untergang (rechts) → Mitte der Nacht (unten) → Aufgang (links)
            return positionOnArc(angle: -progress * Double.pi)

        case .morning, .afternoon, .evening:
            guard let sunrise = today.sunrise, let sunset = today.sunset else {
                return fallbackPosition(for: phase, ebbeTime: ebbeTime)
            }
            let span = sunset.timeIntervalSince(sunrise)
            guard span > 0 else { return positionOnArc(angle: .pi * 0.5) }
            let progress = min(1, max(0, ebbeTime.timeIntervalSince(sunrise) / span))
            // Oberer Halbkreis: Aufgang (links) → Mittag (oben) → Untergang (rechts)
            return positionOnArc(angle: Double.pi * (1 - progress))
        }
    }

    private static func positionOnArc(angle: Double) -> (x: Double, y: Double) {
        let x = arcCenterFraction + arcRadiusFraction * cos(angle)
        let y = arcCenterFraction - arcRadiusFraction * sin(angle)
        return (x, y)
    }

    private static func nightWindow(ebbeTime: Date, referenceDay: Date) -> (start: Date, end: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone

        let dayStart = cal.startOfDay(for: referenceDay)
        let today = astronomy(for: referenceDay)
        guard let sunrise = today.sunrise, let sunset = today.sunset else { return nil }

        if ebbeTime < sunrise {
            let yesterday = cal.date(byAdding: .day, value: -1, to: dayStart)!
            guard let nightStart = astronomy(for: yesterday).sunset else { return nil }
            return (nightStart, sunrise)
        }
        if ebbeTime >= sunset {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: dayStart)!
            guard let nightEnd = astronomy(for: tomorrow).sunrise else { return nil }
            return (sunset, nightEnd)
        }
        return nil
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

    private static func fallbackPosition(for phase: EbbeDayPhase, ebbeTime: Date) -> (x: Double, y: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let hour = cal.component(.hour, from: ebbeTime)
        let minute = cal.component(.minute, from: ebbeTime)
        let dayFraction = (Double(hour) + Double(minute) / 60.0) / 24.0

        switch phase {
        case .beforeSunrise, .afterSunset:
            let progress = dayFraction >= 0.75
                ? (dayFraction - 0.75) / 0.25
                : (dayFraction + 0.25) / 0.25
            return positionOnArc(angle: -min(1, max(0, progress)) * Double.pi)
        case .morning, .afternoon, .evening:
            let progress = min(1, max(0, (dayFraction - 0.25) / 0.50))
            return positionOnArc(angle: Double.pi * (1 - progress))
        }
    }
}
