import Foundation

actor TideService {
    static let shared = TideService()

    private let stationID = "56"  // Puerto de la Luz, Gran Canaria
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
    /// Uses cache for already-loaded days; only fetches missing ones from the network.
    func fetchTides(forDays days: Int, timeOffsetMinutes: Int) async throws -> [TideDay] {
        let today = Calendar.current.startOfDay(for: Date())

        // Determine which dates are missing from cache
        let allDates = (0..<days).map { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: today)!
        }

        let cachedDays = await loadFromCache(dates: allDates, timeOffsetMinutes: timeOffsetMinutes)
        let cachedDateKeys = Set(cachedDays.map { TideCache.dateKey($0.date) })
        let missingDates = allDates.filter { !cachedDateKeys.contains(TideCache.dateKey($0)) }

        // Fetch missing days in parallel
        var fetchedDays: [TideDay] = []
        if !missingDates.isEmpty {
            fetchedDays = try await fetchFromNetwork(dates: missingDates, timeOffsetMinutes: timeOffsetMinutes)
        }

        // Merge and sort
        let allDays = (cachedDays + fetchedDays).sorted { $0.date < $1.date }
        return allDays
    }

    // MARK: - Network

    private func fetchFromNetwork(dates: [Date], timeOffsetMinutes: Int) async throws -> [TideDay] {
        try await withThrowingTaskGroup(of: TideDay.self) { group in
            for date in dates {
                group.addTask {
                    let response = try await self.fetchRawResponse(for: date)
                    await TideCache.shared.save(response, for: date)
                    return self.parseDay(from: response.mareas, referenceDate: date, timeOffsetMinutes: timeOffsetMinutes)
                }
            }
            var results: [TideDay] = []
            for try await day in group { results.append(day) }
            return results
        }
    }

    private func fetchRawResponse(for date: Date) async throws -> IHMResponse {
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
            if let response = await TideCache.shared.load(for: date) {
                let day = parseDay(from: response.mareas, referenceDate: date, timeOffsetMinutes: timeOffsetMinutes)
                days.append(day)
            }
        }
        return days
    }

    // MARK: - Parsing

    private func parseDay(from mareas: IHMMareas, referenceDate: Date, timeOffsetMinutes: Int) -> TideDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.canaryIslandsTimeZone

        let events: [TideEvent] = mareas.datos.marea.compactMap { marea in
            guard let tideType = TideType(rawValue: marea.tipo),
                  let height = Double(marea.altura),
                  let originalTime = parseTime(marea.hora, referenceDate: referenceDate, calendar: cal)
            else { return nil }

            let adjustedTime = Calendar.current.date(
                byAdding: .minute, value: timeOffsetMinutes, to: originalTime
            ) ?? originalTime

            return TideEvent(
                originalTime: originalTime,
                adjustedTime: adjustedTime,
                height: height,
                type: tideType,
                date: referenceDate
            )
        }
        return TideDay(date: referenceDate, events: events.sorted { $0.adjustedTime < $1.adjustedTime })
    }

    private func parseTime(_ timeString: String, referenceDate: Date, calendar: Calendar) -> Date? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = 0
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
