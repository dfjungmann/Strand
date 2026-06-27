import Foundation

actor TideService {
    static let shared = TideService()

    // IHM stations used for interpolation (Playa del Águila ~27.777°N, 15.527°W)
    private let stationArinaga = "57"       // Arinaga, Ostküste  27.847°N
    private let stationPasitoBlanco = "58"  // Pasito Blanco, Südküste  27.747°N

    // Distance-based weights: Pasito Blanco is closer → 60 %
    private static let weightArinaga: Double = 0.4
    private static let weightPasitoBlanco: Double = 0.6

    private let baseURL = "https://ideihm.covam.es/api-ihm/getmarea"

    static let canaryIslandsTimeZone = TimeZone(identifier: "Atlantic/Canary")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Fetches tide data for `days` days starting from today.
    /// Loads from cache where available; fetches missing days from both stations in parallel.
    func fetchTides(forDays days: Int, timeOffsetMinutes: Int) async throws -> [TideDay] {
        let today = Calendar.current.startOfDay(for: Date())

        let allDates = (0..<days).map { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: today)!
        }

        let cachedDays = await loadFromCache(dates: allDates, timeOffsetMinutes: timeOffsetMinutes)
        let cachedDateKeys = Set(cachedDays.map { TideCache.dateKey($0.date) })
        let missingDates = allDates.filter { !cachedDateKeys.contains(TideCache.dateKey($0)) }

        var fetchedDays: [TideDay] = []
        if !missingDates.isEmpty {
            fetchedDays = try await fetchFromNetwork(dates: missingDates, timeOffsetMinutes: timeOffsetMinutes)
        }

        return (cachedDays + fetchedDays).sorted { $0.date < $1.date }
    }

    // MARK: - Network

    private func fetchFromNetwork(dates: [Date], timeOffsetMinutes: Int) async throws -> [TideDay] {
        // Pre-capture station IDs so they can be used inside @Sendable task closures
        let sid57 = stationArinaga
        let sid58 = stationPasitoBlanco
        return try await withThrowingTaskGroup(of: TideDay.self) { group in
            for date in dates {
                group.addTask {
                    // Fetch both stations in parallel
                    async let r57 = self.fetchRawResponse(for: date, stationID: sid57)
                    async let r58 = self.fetchRawResponse(for: date, stationID: sid58)
                    let (arinaga, pasitoBlanco) = try await (r57, r58)
                    await TideCache.shared.save(arinaga, for: date, stationID: sid57)
                    await TideCache.shared.save(pasitoBlanco, for: date, stationID: sid58)
                    return self.interpolateDay(
                        arinaga: arinaga.mareas,
                        pasitoBlanco: pasitoBlanco.mareas,
                        referenceDate: date,
                        timeOffsetMinutes: timeOffsetMinutes
                    )
                }
            }
            var results: [TideDay] = []
            for try await day in group { results.append(day) }
            return results
        }
    }

    private func fetchRawResponse(for date: Date, stationID: String) async throws -> IHMResponse {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "request", value: "gettide"),
            URLQueryItem(name: "id", value: stationID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "date", value: TideCache.dateKey(date))
        ]
        guard let url = components.url else { throw TideServiceError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TideServiceError.invalidResponse
        }
        return try JSONDecoder().decode(IHMResponse.self, from: data)
    }

    // MARK: - Cache

    private func loadFromCache(dates: [Date], timeOffsetMinutes: Int) async -> [TideDay] {
        var days: [TideDay] = []
        for date in dates {
            guard let arinaga = await TideCache.shared.load(for: date, stationID: stationArinaga),
                  let pasitoBlanco = await TideCache.shared.load(for: date, stationID: stationPasitoBlanco)
            else { continue }
            let day = interpolateDay(
                arinaga: arinaga.mareas,
                pasitoBlanco: pasitoBlanco.mareas,
                referenceDate: date,
                timeOffsetMinutes: timeOffsetMinutes
            )
            days.append(day)
        }
        return days
    }

    // MARK: - Interpolation

    /// Merges tide events from Arinaga and Pasito Blanco using distance-weighted averaging.
    /// Events are matched by type and ordinal position (1st high tide ↔ 1st high tide, etc.).
    /// If one station has fewer events for a day, the available station's data is used as-is.
    nonisolated private func interpolateDay(
        arinaga: IHMMareas,
        pasitoBlanco: IHMMareas,
        referenceDate: Date,
        timeOffsetMinutes: Int
    ) -> TideDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone

        typealias RawEvent = (type: TideType, time: Date, height: Double)

        func parseRaw(_ mareas: [IHMMarea]) -> [RawEvent] {
            mareas.compactMap { m in
                guard let type = TideType(rawValue: m.tipo),
                      let height = Double(m.altura),
                      let time = Self.parseTime(m.hora, referenceDate: referenceDate, calendar: cal)
                else { return nil }
                return (type, time, height)
            }.sorted { $0.time < $1.time }
        }

        let aEvents = parseRaw(arinaga.datos.marea)
        let pEvents = parseRaw(pasitoBlanco.datos.marea)

        let aHigh = aEvents.filter { $0.type == .highTide }
        let aLow  = aEvents.filter { $0.type == .lowTide }
        let pHigh = pEvents.filter { $0.type == .highTide }
        let pLow  = pEvents.filter { $0.type == .lowTide }

        func blend(_ a: RawEvent?, _ p: RawEvent?, type: TideType) -> TideEvent? {
            let wA = Self.weightArinaga
            let wP = Self.weightPasitoBlanco
            let (origTime, height): (Date, Double)
            switch (a, p) {
            case let (.some(ae), .some(pe)):
                let t = ae.time.timeIntervalSince1970 * wA + pe.time.timeIntervalSince1970 * wP
                origTime = Date(timeIntervalSince1970: t)
                height = ae.height * wA + pe.height * wP
            case let (.some(ae), .none):
                origTime = ae.time; height = ae.height
            case let (.none, .some(pe)):
                origTime = pe.time; height = pe.height
            case (.none, .none):
                return nil
            }
            let adj = Calendar.current.date(byAdding: .minute, value: timeOffsetMinutes, to: origTime) ?? origTime
            return TideEvent(originalTime: origTime, adjustedTime: adj, height: height, type: type, date: referenceDate)
        }

        var events: [TideEvent] = []
        for i in 0..<max(aHigh.count, pHigh.count) {
            if let e = blend(i < aHigh.count ? aHigh[i] : nil,
                             i < pHigh.count ? pHigh[i] : nil,
                             type: .highTide) { events.append(e) }
        }
        for i in 0..<max(aLow.count, pLow.count) {
            if let e = blend(i < aLow.count ? aLow[i] : nil,
                             i < pLow.count ? pLow[i] : nil,
                             type: .lowTide) { events.append(e) }
        }

        return TideDay(date: referenceDate, events: events.sorted { $0.adjustedTime < $1.adjustedTime })
    }

    nonisolated private static func parseTime(_ timeString: String, referenceDate: Date, calendar: Calendar) -> Date? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        // IHM publishes tide times in UTC (standard for maritime data).
        // We take the calendar date in Canary time (matching the queried date) but
        // override the time zone to UTC so the hours/minutes are interpreted correctly.
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour   = parts[0]
        components.minute = parts[1]
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: components)
    }
}

// MARK: - Errors

enum TideServiceError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige URL"
        case .invalidResponse: return "Ungültige Server-Antwort"
        }
    }
}
