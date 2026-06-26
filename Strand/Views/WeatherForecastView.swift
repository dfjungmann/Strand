import SwiftUI

// MARK: - Location model

struct ForecastLocation: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let timezone: String
}

let forecastLocations: [ForecastLocation] = [
    ForecastLocation(id: "pda",  name: "Playa del Aguila",      shortName: "PdA",  subtitle: "Gran Canaria",     latitude: 27.754, longitude: -15.571, timezone: "Atlantic/Canary"),
    ForecastLocation(id: "pdlc", name: "Puerto de la Cruz",     shortName: "PdC",  subtitle: "Teneriffa",        latitude: 28.414, longitude: -16.548, timezone: "Atlantic/Canary"),
    ForecastLocation(id: "pdla", name: "Playa de las Américas", shortName: "PdAm", subtitle: "Teneriffa",        latitude: 28.058, longitude: -16.724, timezone: "Atlantic/Canary"),
    ForecastLocation(id: "gb",   name: "Gladbeck",              shortName: "Gla",  subtitle: "NRW, Deutschland", latitude: 51.570, longitude:   7.002, timezone: "Europe/Berlin"),
    ForecastLocation(id: "bt",   name: "Baiersbronn Tonbach",   shortName: "Ton",  subtitle: "BW, Deutschland",  latitude: 48.513, longitude:   8.355, timezone: "Europe/Berlin"),
]

// MARK: - Daily forecast model

struct DailyForecast: Identifiable {
    let id = UUID()
    let date: Date
    let weatherCode: Int
    let tempMax: Double
    let tempMin: Double
    let precipProbMax: Int
    let precipSum: Double
    let sunshineHours: Double
    let windspeedMax: Double
    let windDirectionDominant: Int
    let uvIndexMax: Double
    let sunrise: Date?
    let sunset: Date?
}

struct HourlyForecastPoint: Identifiable {
    let id = UUID()
    let time: Date
    let weatherCode: Int
    let temperature: Double
    let precipProb: Int
    let precipSum: Double
    let windspeed: Double
    let windDirection: Int
}

// MARK: - Open-Meteo response

private struct OMResponse: Codable {
    let daily: OMDaily
    let hourly: OMHourly
}

private struct OMDaily: Codable {
    let time: [String]
    let weathercode: [Int?]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]
    let precipitationProbabilityMax: [Int?]
    let precipitationSum: [Double?]
    let sunshineDuration: [Double?]
    let windspeed10mMax: [Double?]
    let winddirection10mDominant: [Int?]
    let uvIndexMax: [Double?]
    let sunrise: [String?]
    let sunset: [String?]

    enum CodingKeys: String, CodingKey {
        case time
        case weathercode
        case temperature2mMax               = "temperature_2m_max"
        case temperature2mMin               = "temperature_2m_min"
        case precipitationProbabilityMax    = "precipitation_probability_max"
        case precipitationSum               = "precipitation_sum"
        case sunshineDuration               = "sunshine_duration"
        case windspeed10mMax                = "windspeed_10m_max"
        case winddirection10mDominant       = "winddirection_10m_dominant"
        case uvIndexMax                     = "uv_index_max"
        case sunrise
        case sunset
    }
}

private struct OMHourly: Codable {
    let time: [String]
    let temperature2m: [Double?]
    let weathercode: [Int?]
    let precipitationProbability: [Int?]
    let precipitation: [Double?]
    let windspeed10m: [Double?]
    let winddirection10m: [Int?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m            = "temperature_2m"
        case weathercode
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case windspeed10m             = "windspeed_10m"
        case winddirection10m         = "winddirection_10m"
    }
}

// MARK: - Fetch service

private actor ForecastService {
    static let shared = ForecastService()

    func fetch(location: ForecastLocation) async throws -> (daily: [DailyForecast], hourly: [HourlyForecastPoint]) {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude",      value: "\(location.latitude)"),
            URLQueryItem(name: "longitude",     value: "\(location.longitude)"),
            URLQueryItem(name: "daily",         value: "weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunshine_duration,windspeed_10m_max,winddirection_10m_dominant,uv_index_max,sunrise,sunset"),
            URLQueryItem(name: "hourly",        value: "temperature_2m,weathercode,precipitation_probability,precipitation,windspeed_10m,winddirection_10m"),
            URLQueryItem(name: "timezone",      value: location.timezone),
            URLQueryItem(name: "forecast_days", value: "14"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let decoded   = try JSONDecoder().decode(OMResponse.self, from: data)
        let daily     = parseDaily(decoded.daily, timezone: location.timezone)
        let hourly    = parseHourly(decoded.hourly, timezone: location.timezone)
        return (daily: daily, hourly: hourly)
    }

    private func parseDaily(_ d: OMDaily, timezone: String) -> [DailyForecast] {
        let tz  = TimeZone(identifier: timezone) ?? .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone   = tz

        let dtFmt = DateFormatter()
        dtFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        dtFmt.timeZone   = tz

        return d.time.enumerated().compactMap { (idx, dateStr) -> DailyForecast? in
            guard let date = fmt.date(from: dateStr) else { return nil }

            let sunriseStr = d.sunrise[safeIdx: idx].flatMap { $0 }
            let sunsetStr  = d.sunset[safeIdx: idx].flatMap { $0 }

            return DailyForecast(
                date: date,
                weatherCode:           d.weathercode[safeIdx: idx].flatMap { $0 }                 ?? 0,
                tempMax:               d.temperature2mMax[safeIdx: idx].flatMap { $0 }            ?? 0,
                tempMin:               d.temperature2mMin[safeIdx: idx].flatMap { $0 }            ?? 0,
                precipProbMax:         d.precipitationProbabilityMax[safeIdx: idx].flatMap { $0 } ?? 0,
                precipSum:             d.precipitationSum[safeIdx: idx].flatMap { $0 }            ?? 0,
                sunshineHours:        (d.sunshineDuration[safeIdx: idx].flatMap { $0 }            ?? 0) / 3600,
                windspeedMax:          d.windspeed10mMax[safeIdx: idx].flatMap { $0 }             ?? 0,
                windDirectionDominant: d.winddirection10mDominant[safeIdx: idx].flatMap { $0 }    ?? 0,
                uvIndexMax:            d.uvIndexMax[safeIdx: idx].flatMap { $0 }                  ?? 0,
                sunrise:               sunriseStr.flatMap { dtFmt.date(from: $0) },
                sunset:                sunsetStr.flatMap  { dtFmt.date(from: $0) }
            )
        }
    }

    private func parseHourly(_ h: OMHourly, timezone: String) -> [HourlyForecastPoint] {
        let tz  = TimeZone(identifier: timezone) ?? .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone   = tz

        return h.time.enumerated().compactMap { (idx, timeStr) -> HourlyForecastPoint? in
            guard let time = fmt.date(from: timeStr) else { return nil }
            return HourlyForecastPoint(
                time:        time,
                weatherCode: h.weathercode[safeIdx: idx].flatMap { $0 }              ?? 0,
                temperature: h.temperature2m[safeIdx: idx].flatMap { $0 }            ?? 0,
                precipProb:  h.precipitationProbability[safeIdx: idx].flatMap { $0 } ?? 0,
                precipSum:   h.precipitation[safeIdx: idx].flatMap { $0 }            ?? 0,
                windspeed:   h.windspeed10m[safeIdx: idx].flatMap { $0 }             ?? 0,
                windDirection: h.winddirection10m[safeIdx: idx].flatMap { $0 }       ?? 0
            )
        }
    }
}

private extension Array {
    subscript(safeIdx index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - WMO code helpers

/// Open-Meteo's daily weathercode picks the worst event of the day.
/// If sunshine hours are high and rain probability is low, correct an overly
/// pessimistic code so the icon matches what the day actually feels like.
private func correctedCode(_ code: Int, sunshineHours: Double = 0, precipProb: Int, precipSum: Double = 0) -> Int {
    let rainLikely = precipProb >= 30 || precipSum >= 0.5
    if !rainLikely && code >= 51 {
        return sunshineHours >= 10 ? 1 : (sunshineHours >= 6 ? 2 : 3)
    }
    guard precipProb < 20 && precipSum < 0.5 else { return code }
    if code == 3 && sunshineHours >= 10 { return 1 }
    if code == 3 && sunshineHours >= 6  { return 2 }
    if code == 2 && sunshineHours >= 11 { return 1 }
    return code
}

private func wmoSymbol(_ code: Int, isNight: Bool = false) -> String {
    if isNight {
        switch code {
        case 0, 1: return "moon.stars.fill"
        case 2:    return "cloud.moon.fill"
        default:   break
        }
    }
    switch code {
    case 0, 1:    return "sun.max.fill"
    case 2:       return "cloud.sun.fill"
    case 3:       return "cloud.fill"
    case 45, 48:  return "cloud.fog.fill"
    case 51...57: return "cloud.drizzle.fill"
    case 61...67: return "cloud.rain.fill"
    case 71...77: return "cloud.snow.fill"
    case 80...82: return "cloud.heavyrain.fill"
    case 85, 86:  return "cloud.snow.fill"
    case 95:      return "cloud.bolt.rain.fill"
    case 96, 99:  return "cloud.bolt.rain.fill"
    default:      return "cloud.fill"
    }
}

private func wmoColor(_ code: Int, isNight: Bool = false) -> Color {
    if isNight {
        switch code {
        case 0, 1: return Color(.systemGray)
        case 2:    return Color(.systemGray2)
        default:   break
        }
    }
    switch code {
    case 0, 1:    return .yellow
    case 2:       return .orange
    case 3:       return Color(.systemGray2)
    case 45, 48:  return Color(.systemGray3)
    case 51...57: return .teal
    case 61...67: return .blue
    case 71...77: return .cyan
    case 80...82: return .blue
    case 85, 86:  return .cyan
    case 95...99: return .purple
    default:      return Color(.systemGray2)
    }
}

private func wmoDescription(_ code: Int) -> String {
    switch code {
    case 0:       return "Klar"
    case 1:       return "Heiter"
    case 2:       return "Wechselh."
    case 3:       return "Bewölkt"
    case 45, 48:  return "Nebel"
    case 51...57: return "Nieselregen"
    case 61...67: return "Regen"
    case 71...77: return "Schnee"
    case 80...82: return "Schauer"
    case 85, 86:  return "Schneeschauer"
    case 95:      return "Gewitter"
    case 96, 99:  return "Starkes Gewitter"
    default:      return ""
    }
}

private func windArrow(_ degrees: Int) -> String {
    let arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
    return arrows[Int((Double(degrees) + 22.5) / 45.0) % 8]
}

// MARK: - Main view

struct WeatherForecastView: View {
    @AppStorage("shared_location_id") private var selectedLocationId: String = forecastLocations[0].id
    private var selectedLocation: ForecastLocation {
        forecastLocations.first { $0.id == selectedLocationId } ?? forecastLocations[0]
    }
    @State private var forecasts: [DailyForecast] = []
    @State private var hourlyPoints: [HourlyForecastPoint] = []
    @State private var selectedDay: DailyForecast? = nil
    @State private var isLoading = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Header (wie Radar-Tab) ──
                VStack(spacing: 6) {
                    HStack {
                        Text("Wetter · \(selectedLocation.name)")
                            .font(.headline)
                        Spacer()
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Picker("Ort", selection: $selectedLocationId) {
                        ForEach(forecastLocations) { loc in
                            Text(loc.shortName).tag(loc.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)

                    Color.clear.frame(height: 4)
                }
                .background(.bar)

                Divider()

                if let err = errorMsg {
                    Spacer()
                    Text(err).foregroundStyle(.secondary).padding()
                    Spacer()
                } else {
                    forecastList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedDay) { day in
                DayForecastDetailView(
                    initialDayID: day.id,
                    days: forecasts,
                    hourly: hourlyPoints,
                    timezone: selectedLocation.timezone,
                    locationName: selectedLocation.name
                )
            }
        }
        .task(id: selectedLocation.id) { await load() }
    }

    // MARK: Forecast list

    private var forecastList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(forecasts.enumerated()), id: \.element.id) { idx, day in
                    ForecastRow(day: day, isToday: idx == 0) {
                        selectedDay = day
                    }
                    if idx < forecasts.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        errorMsg  = nil
        defer { isLoading = false }
        do {
            let result   = try await ForecastService.shared.fetch(location: selectedLocation)
            forecasts    = result.daily
            hourlyPoints = result.hourly
        } catch {
            errorMsg = "Daten konnten nicht geladen werden."
        }
    }
}

// MARK: - Forecast row

private struct ForecastRow: View {
    let day: DailyForecast
    let isToday: Bool
    let onTap: () -> Void

    private var dayName: String {
        if isToday { return "Heute" }
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "de_DE")
        fmt.dateFormat = "EEE"
        return fmt.string(from: day.date)
    }

    private var dateStr: String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "de_DE")
        fmt.dateFormat = "d.M."
        return fmt.string(from: day.date)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 1. Day + date — fixed width
            VStack(alignment: .leading, spacing: 2) {
                Text(dayName)
                    .font(.system(.subheadline, design: .rounded).weight(isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                Text(dateStr)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60, alignment: .leading)

            // 2. Weather icon + description — fixed width
            VStack(spacing: 2) {
                let eff = correctedCode(day.weatherCode, sunshineHours: day.sunshineHours, precipProb: day.precipProbMax, precipSum: day.precipSum)
                Image(systemName: wmoSymbol(eff))
                    .font(.system(size: 28))
                    .foregroundStyle(wmoColor(eff))
                    .frame(width: 36, height: 32)
                Text(wmoDescription(eff))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 44)
            }
            .frame(width: 48)

            // 3. Temperatures max/min — fixed width
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(day.tempMax.rounded()))°")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.orange)
                Text("\(Int(day.tempMin.rounded()))°")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, alignment: .trailing)

            Spacer(minLength: 8)

            // 4. Sunshine + precip — flexible, centered
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "sun.max.fill").foregroundStyle(.yellow).font(.caption2)
                    Text(String(format: "%.1fh", day.sunshineHours))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "drop.fill").foregroundStyle(.blue).font(.caption2)
                    Text("\(day.precipProbMax)%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(day.precipProbMax > 40 ? .blue : .secondary)
                    Text(String(format: "%.1fmm", day.precipSum))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 80)

            Spacer(minLength: 8)

            // 5. Wind — trailing, single line, enough room for "↙ 188 km/h"
            Text("\(windArrow(day.windDirectionDominant)) \(Int(day.windspeedMax.rounded())) km/h")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.teal)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isToday ? Color.accentColor.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Day detail view

struct DayForecastDetailView: View {
    let initialDayID: UUID
    let days: [DailyForecast]
    let hourly: [HourlyForecastPoint]
    let timezone: String
    let locationName: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDayID: UUID

    init(initialDayID: UUID, days: [DailyForecast], hourly: [HourlyForecastPoint], timezone: String, locationName: String) {
        self.initialDayID = initialDayID
        self.days = days
        self.hourly = hourly
        self.timezone = timezone
        self.locationName = locationName
        _selectedDayID = State(initialValue: initialDayID)
    }

    private var selectedDay: DailyForecast? {
        days.first { $0.id == selectedDayID }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedDayID) {
                ForEach(days) { day in
                    DayDetailPageView(
                        day: day,
                        hourly: hourly,
                        timezone: timezone
                    )
                    .tag(day.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(titleFor(selectedDay))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func titleFor(_ day: DailyForecast?) -> String {
        guard let day else { return locationName }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "EEEE, d. MMMM"
        fmt.timeZone = TimeZone(identifier: timezone) ?? .current
        return "\(fmt.string(from: day.date)) · \(locationName)"
    }
}

private struct DayDetailPageView: View {
    let day: DailyForecast
    let hourly: [HourlyForecastPoint]
    let timezone: String

    private var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    private var dayHourly: [HourlyForecastPoint] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return hourly.filter { cal.isDate($0.time, inSameDayAs: day.date) }
    }

    private func timeStr(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = tz
        return fmt.string(from: date)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Day summary card ─────────────────────────────
                VStack(spacing: 12) {
                    let eff = correctedCode(day.weatherCode, sunshineHours: day.sunshineHours, precipProb: day.precipProbMax, precipSum: day.precipSum)
                    HStack(spacing: 16) {
                        Image(systemName: wmoSymbol(eff))
                            .font(.system(size: 52))
                            .foregroundStyle(wmoColor(eff))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(wmoDescription(eff))
                                .font(.headline)
                            HStack(spacing: 12) {
                                Label("\(Int(day.tempMax.rounded()))°", systemImage: "thermometer.high")
                                    .foregroundStyle(.orange)
                                    .font(.title3.weight(.semibold))
                                Label("\(Int(day.tempMin.rounded()))°", systemImage: "thermometer.low")
                                    .foregroundStyle(.blue)
                                    .font(.title3)
                            }
                        }
                        Spacer()
                    }

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCell(icon: "sun.max.fill",  color: .yellow, label: "Sonne",   value: String(format: "%.1fh", day.sunshineHours))
                        StatCell(icon: "drop.fill",     color: .blue,   label: "Regen",   value: String(format: "%d%%  %.1fmm", day.precipProbMax, day.precipSum))
                        StatCell(icon: "wind",          color: .teal,   label: "Wind",    value: String(format: "%.0f km/h", day.windspeedMax))
                        if let sr = day.sunrise {
                            StatCell(icon: "sunrise.fill", color: .orange, label: "Aufgang", value: timeStr(sr))
                        }
                        if let ss = day.sunset {
                            StatCell(icon: "sunset.fill",  color: .orange, label: "Untergang", value: timeStr(ss))
                        }
                        StatCell(icon: "sun.dust.fill", color: .yellow, label: "UV-Index", value: String(format: "%.0f", day.uvIndexMax))
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))

                Divider()

                // ── Hourly rows ──────────────────────────────────
                if dayHourly.isEmpty {
                    Text("Keine Stundendaten verfügbar")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(dayHourly.enumerated()), id: \.element.id) { idx, h in
                            HourlyRow(point: h, timezone: timezone,
                                      sunrise: day.sunrise, sunset: day.sunset)
                            if idx < dayHourly.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct StatCell: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct HourlyRow: View {
    let point: HourlyForecastPoint
    let timezone: String
    let sunrise: Date?
    let sunset: Date?

    private var isNight: Bool {
        guard let sr = sunrise, let ss = sunset else { return false }
        return point.time < sr || point.time > ss
    }

    private var timeStr: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone   = TimeZone(identifier: timezone) ?? .current
        return fmt.string(from: point.time)
    }

    var body: some View {
        let effCode = correctedCode(point.weatherCode, precipProb: point.precipProb, precipSum: point.precipSum)
        HStack(spacing: 6) {
            // Zeit – feste Breite, kein fixedSize
            Text(timeStr)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .frame(width: 50, alignment: .leading)
                .foregroundStyle(isNight ? Color(.systemGray) : .secondary)

            // Wetter-Icon
            Image(systemName: wmoSymbol(effCode, isNight: isNight))
                .font(.system(size: 22))
                .foregroundStyle(wmoColor(effCode, isNight: isNight))
                .frame(width: 28, alignment: .center)

            // Temperatur – feste Breite
            Text("\(Int(point.temperature.rounded()))°")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 40, alignment: .leading)

            Spacer(minLength: 4)

            // Niederschlag
            HStack(spacing: 3) {
                Image(systemName: "drop.fill").foregroundStyle(.blue).font(.caption2)
                Text("\(point.precipProb)%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(point.precipProb > 40 ? .blue : .secondary)
                Text(String(format: "%.1fmm", point.precipSum))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            // Wind
            Text("\(windArrow(point.windDirection)) \(Int(point.windspeed.rounded())) km/h")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.teal)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
