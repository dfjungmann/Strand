import Foundation

// MARK: - Data Models

struct AstronomyData {
    let sunrise: Date?
    let sunset: Date?
    let moonPhase: MoonPhase
    let moonAngle: Double   // 0.0 (Neumond) … 1.0
}

enum MoonPhase: String {
    case newMoon        = "Neumond"
    case waxingCrescent = "Zunehmende Sichel"
    case firstQuarter   = "Erstes Viertel"
    case waxingGibbous  = "Zunehmend"
    case fullMoon       = "Vollmond"
    case waningGibbous  = "Abnehmend"
    case lastQuarter    = "Letztes Viertel"
    case waningCrescent = "Abnehmende Sichel"

    var emoji: String {
        switch self {
        case .newMoon:        return "🌑"
        case .waxingCrescent: return "🌒"
        case .firstQuarter:   return "🌓"
        case .waxingGibbous:  return "🌔"
        case .fullMoon:       return "🌕"
        case .waningGibbous:  return "🌖"
        case .lastQuarter:    return "🌗"
        case .waningCrescent: return "🌘"
        }
    }
}

// MARK: - Astronomy Service

struct AstronomyService {

    /// Coordinates for Playa del Aguila, Gran Canaria
    static let latitude  =  27.754
    static let longitude = -15.571

    static func data(for date: Date) -> AstronomyData {
        let (sunrise, sunset) = sunriseSunset(date: date, lat: latitude, lon: longitude)
        let (phase, angle)   = moonPhase(for: date)
        return AstronomyData(sunrise: sunrise, sunset: sunset, moonPhase: phase, moonAngle: angle)
    }

    // MARK: - Sunrise / Sunset  (NOAA Solar Calculator algorithm)

    static func sunriseSunset(date: Date, lat: Double, lon: Double) -> (sunrise: Date?, sunset: Date?) {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TideService.canaryIslandsTimeZone
        let c = localCal.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return (nil, nil) }

        let jd = julianDay(year: y, month: m, day: d)

        let riseUTC = sunriseSetUTC(rise: true,  jd: jd, lat: lat, lon: lon)
        let setUTC  = sunriseSetUTC(rise: false, jd: jd, lat: lat, lon: lon)

        func toDate(_ minutes: Double) -> Date? {
            guard minutes.isFinite else { return nil }
            var utcCal = Calendar(identifier: .gregorian)
            utcCal.timeZone = TimeZone(identifier: "UTC")!
            var base = DateComponents()
            base.year = y; base.month = m; base.day = d
            base.hour = 0; base.minute = 0; base.second = 0
            guard let start = utcCal.date(from: base) else { return nil }
            return start.addingTimeInterval(minutes * 60)
        }
        return (toDate(riseUTC), toDate(setUTC))
    }

    // MARK: NOAA helpers

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = Int(Double(y) / 100)
        let b = 2 - a + Int(Double(a) / 4)
        return Double(Int(365.25 * Double(y + 4716)))
             + Double(Int(30.6001 * Double(m + 1)))
             + Double(day) + Double(b) - 1524.5
    }

    private static func jCent(_ jd: Double) -> Double { (jd - 2451545) / 36525 }

    private static func geomMeanLongSun(_ t: Double) -> Double {
        var l = 280.46646 + t * (36000.76983 + t * 0.0003032)
        l = l.truncatingRemainder(dividingBy: 360)
        return l < 0 ? l + 360 : l
    }

    private static func geomMeanAnomalySun(_ t: Double) -> Double {
        357.52911 + t * (35999.05029 - 0.0001537 * t)
    }

    private static func eccentricity(_ t: Double) -> Double {
        0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    }

    private static func sunEqCenter(_ t: Double) -> Double {
        let m  = geomMeanAnomalySun(t) * .pi / 180
        return sin(m)   * (1.914602 - t * (0.004817 + 0.000014 * t))
             + sin(2*m) * (0.019993 - 0.000101 * t)
             + sin(3*m) * 0.000289
    }

    private static func sunApparentLong(_ t: Double) -> Double {
        let trueLong = geomMeanLongSun(t) + sunEqCenter(t)
        let omega = (125.04 - 1934.136 * t) * .pi / 180
        return trueLong - 0.00569 - 0.00478 * sin(omega)
    }

    private static func obliquityCorrection(_ t: Double) -> Double {
        let sec = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        let e0  = 23 + (26 + sec / 60) / 60
        let omega = (125.04 - 1934.136 * t) * .pi / 180
        return e0 + 0.00256 * cos(omega)
    }

    private static func solarDeclination(_ t: Double) -> Double {
        let e      = obliquityCorrection(t) * .pi / 180
        let lambda = sunApparentLong(t)     * .pi / 180
        return asin(sin(e) * sin(lambda)) * 180 / .pi
    }

    private static func equationOfTime(_ t: Double) -> Double {
        let eps  = obliquityCorrection(t) * .pi / 180
        let l0   = geomMeanLongSun(t)    * .pi / 180
        let e    = eccentricity(t)
        let m    = geomMeanAnomalySun(t) * .pi / 180
        let y    = tan(eps / 2); let y2 = y * y
        let eot  = y2 * sin(2*l0)
                 - 2 * e * sin(m)
                 + 4 * e * y2 * sin(m) * cos(2*l0)
                 - 0.5 * y2 * y2 * sin(4*l0)
                 - 1.25 * e * e * sin(2*m)
        return eot * 4 * 180 / .pi   // minutes
    }

    private static func hourAngleSunrise(lat: Double, dec: Double) -> Double {
        let latR = lat * .pi / 180
        let decR = dec * .pi / 180
        let arg  = cos(90.833 * .pi / 180) / (cos(latR) * cos(decR)) - tan(latR) * tan(decR)
        return acos(arg) * 180 / .pi   // degrees; NaN if always day/night
    }

    private static func sunriseSetUTC(rise: Bool, jd: Double, lat: Double, lon: Double) -> Double {
        let t       = jCent(jd)
        let eqTime  = equationOfTime(t)
        let dec     = solarDeclination(t)
        var ha      = hourAngleSunrise(lat: lat, dec: dec)
        if !rise { ha = -ha }
        return 720 - 4 * (lon + ha) - eqTime   // minutes from UTC midnight
    }

    // MARK: - Moon Phase

    /// Reference new moon: 2000-01-06 18:14 UTC  (JD 2451550.259)
    private static let referenceNewMoon: Date = {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 6
        c.hour = 18; c.minute = 14; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    private static let synodicMonth = 29.53058867 * 86400.0  // seconds

    static func moonPhase(for date: Date) -> (phase: MoonPhase, angle: Double) {
        var age = date.timeIntervalSince(referenceNewMoon)
            .truncatingRemainder(dividingBy: synodicMonth) / synodicMonth
        if age < 0 { age += 1 }

        let phase: MoonPhase
        switch age {
        case 0..<0.0339:   phase = .newMoon
        case 0.0339..<0.2161: phase = .waxingCrescent
        case 0.2161..<0.2839: phase = .firstQuarter
        case 0.2839..<0.4661: phase = .waxingGibbous
        case 0.4661..<0.5339: phase = .fullMoon
        case 0.5339..<0.7161: phase = .waningGibbous
        case 0.7161..<0.7839: phase = .lastQuarter
        case 0.7839..<0.9661: phase = .waningCrescent
        default:               phase = .newMoon
        }
        return (phase, age)
    }
}
