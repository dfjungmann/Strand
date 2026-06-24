import Foundation

// MARK: - Model

struct WeatherDay: Identifiable {
    let id = UUID()
    let date: Date
    let maxTemp: Double       // °C
    let minTemp: Double       // °C
    let precipProb: Int       // 0–100 %
    let sunshineHours: Double // h/day
    let cloudCover: Int       // 0–100 %

    var precipColor: String {
        switch precipProb {
        case 0..<20:  return "green"
        case 20..<50: return "yellow"
        default:      return "blue"
        }
    }
}

// MARK: - Open-Meteo Response

private struct OpenMeteoResponse: Codable {
    let daily: OpenMeteoDailyData
}

private struct OpenMeteoDailyData: Codable {
    let time: [String]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]
    let precipitationProbabilityMax: [Int?]
    let sunshineDuration: [Double?]       // seconds
    let cloudCoverMean: [Int?]            // %

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2mMax             = "temperature_2m_max"
        case temperature2mMin             = "temperature_2m_min"
        case precipitationProbabilityMax  = "precipitation_probability_max"
        case sunshineDuration             = "sunshine_duration"
        case cloudCoverMean               = "cloud_cover_mean"
    }
}

// MARK: - Service

actor WeatherService {
    static let shared = WeatherService()

    // Playa del Aguila, southern Gran Canaria (27.754°N, 15.571°W)
    // Southern microclimate: consistently sunny, unlike the cloudier north
    private let latitude  = 27.754
    private let longitude = -15.571
    private let baseURL   = "https://api.open-meteo.com/v1/forecast"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 15
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    func fetchWeather(days: Int) async throws -> [WeatherDay] {
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "latitude",    value: String(latitude)),
            URLQueryItem(name: "longitude",   value: String(longitude)),
            URLQueryItem(name: "daily",       value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunshine_duration,cloud_cover_mean"),
            URLQueryItem(name: "timezone",    value: "Atlantic/Canary"),
            URLQueryItem(name: "forecast_days", value: String(days))
        ]
        guard let url = comps.url else { throw WeatherServiceError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return parse(decoded.daily)
    }

    private func parse(_ daily: OpenMeteoDailyData) -> [WeatherDay] {
        let canary = TimeZone(identifier: "Atlantic/Canary")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = canary

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = canary

        return daily.time.enumerated().compactMap { idx, dateStr in
            guard let date    = formatter.date(from: dateStr),
                  let maxT    = daily.temperature2mMax[safe: idx] ?? nil,
                  let minT    = daily.temperature2mMin[safe: idx] ?? nil
            else { return nil }
            let precip   = daily.precipitationProbabilityMax[safe: idx].flatMap { $0 } ?? 0
            let sunshine = (daily.sunshineDuration[safe: idx].flatMap { $0 } ?? 0) / 3600.0
            let cloud    = daily.cloudCoverMean[safe: idx].flatMap { $0 } ?? 0
            return WeatherDay(date: date, maxTemp: maxT, minTemp: minT,
                              precipProb: precip, sunshineHours: sunshine, cloudCover: cloud)
        }
    }
}

// MARK: - Errors

enum WeatherServiceError: LocalizedError {
    case invalidURL, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidURL:      return "Ungültige Wetter-URL"
        case .invalidResponse: return "Ungültige Wetter-Antwort"
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
