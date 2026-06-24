import Foundation

/// File-based cache: stores raw IHMResponse per day as JSON.
/// Cache is independent of time-offset settings — the offset is applied
/// fresh each time data is read from cache.
actor TideCache {
    static let shared = TideCache()

    private let cacheDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = base.appendingPathComponent("TideData", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Interface

    func load(for date: Date) -> IHMResponse? {
        let url = cacheURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IHMResponse.self, from: data)
    }

    func save(_ response: IHMResponse, for date: Date) {
        let url = cacheURL(for: date)
        guard let data = try? JSONEncoder().encode(response) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func isCached(for date: Date) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(for: date).path)
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func clearOlderThan(days: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        for file in files {
            if let dateStr = file.deletingPathExtension().lastPathComponent
                .components(separatedBy: "_").last,
               let fileDate = Self.parseDate(dateStr),
               fileDate < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    var cachedDayCount: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).count) ?? 0
    }

    // MARK: - Helpers

    private func cacheURL(for date: Date) -> URL {
        let key = Self.dateKey(date)
        return cacheDirectory.appendingPathComponent("tide_\(key).json")
    }

    static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TideService.canaryIslandsTimeZone
        return formatter.string(from: date)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TideService.canaryIslandsTimeZone
        return formatter.date(from: string)
    }
}
