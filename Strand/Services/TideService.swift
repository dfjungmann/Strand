import Foundation

actor TideService {
    static let shared = TideService()

    private let stationID = "56"  // Puerto de la Luz, Gran Canaria
    private let baseURL = "https://ideihm.covam.es/api-ihm/getmarea"

    // Canary Islands timezone (UTC+1 in summer, UTC+0 in winter)
    static let canaryIslandsTimeZone = TimeZone(identifier: "Atlantic/Canary")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    func fetchTides(for date: Date, timeOffsetMinutes: Int) async throws -> TideDay {
        let dateString = formatDate(date)
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "request", value: "gettide"),
            URLQueryItem(name: "id", value: stationID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "date", value: dateString)
        ]

        guard let url = components.url else {
            throw TideServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TideServiceError.invalidResponse
        }

        let ihmResponse = try JSONDecoder().decode(IHMResponse.self, from: data)
        return parseDay(from: ihmResponse.mareas, referenceDate: date, timeOffsetMinutes: timeOffsetMinutes)
    }

    func fetchTides(forDays days: Int, timeOffsetMinutes: Int) async throws -> [TideDay] {
        let today = Calendar.current.startOfDay(for: Date())
        return try await withThrowingTaskGroup(of: (Int, TideDay).self) { group in
            for offset in 0..<days {
                let targetDate = Calendar.current.date(byAdding: .day, value: offset, to: today)!
                let index = offset
                group.addTask {
                    let day = try await self.fetchTides(for: targetDate, timeOffsetMinutes: timeOffsetMinutes)
                    return (index, day)
                }
            }

            var results: [(Int, TideDay)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - Parsing

    private func parseDay(from mareas: IHMMareas, referenceDate: Date, timeOffsetMinutes: Int) -> TideDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.canaryIslandsTimeZone

        let events: [TideEvent] = mareas.datos.marea.compactMap { marea in
            guard let tideType = TideType(rawValue: marea.tipo),
                  let height = Double(marea.altura),
                  let originalTime = parseTime(marea.hora, referenceDate: referenceDate, calendar: cal) else {
                return nil
            }
            let adjustedTime = Calendar.current.date(
                byAdding: .minute,
                value: timeOffsetMinutes,
                to: originalTime
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = Self.canaryIslandsTimeZone
        return formatter.string(from: date)
    }
}

// MARK: - Errors

enum TideServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige URL"
        case .invalidResponse: return "Ungültige Server-Antwort"
        case .decodingError(let msg): return "Datenfehler: \(msg)"
        }
    }
}
