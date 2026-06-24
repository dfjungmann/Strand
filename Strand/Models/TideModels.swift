import Foundation

// MARK: - IHM API Response Models

struct IHMResponse: Codable {
    let mareas: IHMMareas
}

struct IHMMareas: Codable {
    let id: String
    let puerto: String
    let fecha: String
    let ndatos: String
    let lat: String
    let lon: String
    let datos: IHMDatos
}

struct IHMDatos: Codable {
    let marea: [IHMMarea]
}

struct IHMMarea: Codable {
    let hora: String
    let altura: String
    let tipo: String
}

// MARK: - App Domain Models

enum TideType: String, CaseIterable, Codable {
    case highTide = "pleamar"
    case lowTide = "bajamar"

    var displayName: String {
        switch self {
        case .highTide: return "Hochwasser"
        case .lowTide: return "Niedrigwasser"
        }
    }

    var symbol: String {
        switch self {
        case .highTide: return "arrow.up.circle.fill"
        case .lowTide: return "arrow.down.circle.fill"
        }
    }
}

struct TideEvent: Identifiable, Equatable, Codable {
    let id: UUID
    let originalTime: Date
    let adjustedTime: Date
    let height: Double
    let type: TideType
    let date: Date

    var isBeachWalkPossible: Bool = false

    init(originalTime: Date, adjustedTime: Date, height: Double, type: TideType, date: Date) {
        self.id = UUID()
        self.originalTime = originalTime
        self.adjustedTime = adjustedTime
        self.height = height
        self.type = type
        self.date = date
    }

    var heightFormatted: String {
        String(format: "%.2f m", height)
    }
}

struct TideDay: Identifiable, Equatable, Codable {
    let id: UUID
    let date: Date
    var events: [TideEvent]

    init(date: Date, events: [TideEvent]) {
        self.id = UUID()
        self.date = date
        self.events = events
    }

    var hasBeachWalkOpportunity: Bool {
        events.contains { $0.isBeachWalkPossible }
    }

    var lowestTide: TideEvent? {
        events.filter { $0.type == .lowTide }.min(by: { $0.height < $1.height })
    }

    var highestTide: TideEvent? {
        events.filter { $0.type == .highTide }.max(by: { $0.height < $1.height })
    }
}

// MARK: - Chart Data Point (continuous curve)

struct TideChartPoint: Identifiable {
    let id = UUID()
    let time: Date
    let height: Double
}
