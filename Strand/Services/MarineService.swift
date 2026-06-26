import Foundation

// MARK: - Model

struct HourlyMarine: Identifiable {
    let id = UUID()
    let time: Date
    let waveHeight: Double?   // m
    let waterTemp: Double?    // °C
}

// MARK: - Service

actor MarineService {
    static let shared = MarineService()
    private init() {}

    private static let canaryTZ = TimeZone(identifier: "Atlantic/Canary")!

    func fetchMarine(days: Int) async throws -> [HourlyMarine] {
        var comps = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        comps.queryItems = [
            URLQueryItem(name: "latitude",      value: "27.754"),
            URLQueryItem(name: "longitude",     value: "-15.571"),
            URLQueryItem(name: "hourly",        value: "wave_height,sea_surface_temperature"),
            URLQueryItem(name: "timezone",      value: "Atlantic/Canary"),
            URLQueryItem(name: "forecast_days", value: "\(days)"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let response = try JSONDecoder().decode(MarineResponse.self, from: data)
        return parseHourly(response.hourly)
    }

    private func parseHourly(_ hourly: MarineHourly) -> [HourlyMarine] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone = Self.canaryTZ

        return hourly.time.enumerated().compactMap { idx, timeStr in
            guard let date = fmt.date(from: timeStr) else { return nil }
            let wave = hourly.waveHeight[safe: idx].flatMap { $0 }
            let temp = hourly.seaSurfaceTemperature[safe: idx].flatMap { $0 }
            return HourlyMarine(time: date, waveHeight: wave, waterTemp: temp)
        }
    }
}

// MARK: - Codable helpers

private struct MarineResponse: Codable {
    let hourly: MarineHourly
}

private struct MarineHourly: Codable {
    let time: [String]
    let waveHeight: [Double?]
    let seaSurfaceTemperature: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case waveHeight              = "wave_height"
        case seaSurfaceTemperature   = "sea_surface_temperature"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
