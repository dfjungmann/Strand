import Foundation

/// Gemeinsame Berechnungen für die Gezeiten-Uhr (iPhone + Watch).
struct TideClockState {
    let now: Date
    let events: [TideEvent]

    var prevEvent: TideEvent? {
        events.last { $0.adjustedTime <= now }
    }

    var nextEvent: TideEvent? {
        events.first { $0.adjustedTime > now }
    }

    var cycleProgress: Double {
        guard let p = prevEvent, let n = nextEvent else { return 0 }
        let elapsed = now.timeIntervalSince(p.adjustedTime)
        let total = n.adjustedTime.timeIntervalSince(p.adjustedTime)
        return max(0, min(1, elapsed / total))
    }

    /// 0° = Flut oben, im Uhrzeigersinn
    var needleAngleDeg: Double {
        guard let p = prevEvent else { return 0 }
        return p.type == .highTide
            ? cycleProgress * 180.0
            : 180.0 + cycleProgress * 180.0
    }

    var tideHeightLabelRotation: Double {
        let a = needleAngleDeg
        return (a > 90 && a < 270) ? a + 180 : a
    }

    var currentHeight: Double {
        guard let p = prevEvent, let n = nextEvent else { return 0 }
        let h0 = p.height, h1 = n.height
        return (h0 + h1) / 2.0 + (h0 - h1) / 2.0 * cos(.pi * cycleProgress)
    }

    var nextIsHigh: Bool { nextEvent?.type == .highTide }

    var nextHighEvent: TideEvent? {
        events.first { $0.adjustedTime > now && $0.type == .highTide }
    }

    var nextLowEvent: TideEvent? {
        events.first { $0.adjustedTime > now && $0.type == .lowTide }
    }

    var cycleHighTide: TideEvent? {
        prevEvent?.type == .highTide ? prevEvent : nextEvent
    }

    var cycleLowTide: TideEvent? {
        prevEvent?.type == .lowTide ? prevEvent : nextEvent
    }

    /// Bogenbreite für ±90 min Strandy-Fenster um Niedrigwasser (180°).
    var beachWalkArcSpan: Double {
        guard let p = prevEvent, let n = nextEvent else { return 24.0 }
        let halfCycleSec = n.adjustedTime.timeIntervalSince(p.adjustedTime)
        return 90.0 * 60.0 / halfCycleSec * 180.0
    }

    var countdownString: String {
        guard let next = nextEvent else { return "" }
        let secs = max(0, next.adjustedTime.timeIntervalSince(now))
        let h = Int(secs) / 3600
        let m = Int(secs) % 3600 / 60
        let s = Int(secs) % 60
        return h > 0
            ? String(format: "%dh %02dm", h, m)
            : String(format: "%dm %02ds", m, s)
    }
}
