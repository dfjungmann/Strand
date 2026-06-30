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

    /// Angezeigtes Extrem an Uhr-Rand: bis 3 h danach „alt“, danach nächstes „neu“.
    enum DisplayedTideRecency {
        case past
        case upcoming
    }

    struct DisplayedTide {
        let event: TideEvent
        let recency: DisplayedTideRecency
    }

    static let labelStickyInterval: TimeInterval = 3 * 3600

    var lastHighTide: TideEvent? {
        events.last { $0.type == .highTide && $0.adjustedTime <= now }
    }

    var lastLowTide: TideEvent? {
        events.last { $0.type == .lowTide && $0.adjustedTime <= now }
    }

    var displayedHighTide: DisplayedTide? {
        displayedExtreme(type: .highTide, last: lastHighTide, next: nextHighEvent)
    }

    var displayedLowTide: DisplayedTide? {
        displayedExtreme(type: .lowTide, last: lastLowTide, next: nextLowEvent)
    }

    private func displayedExtreme(
        type: TideType,
        last: TideEvent?,
        next: TideEvent?
    ) -> DisplayedTide? {
        if let last, now.timeIntervalSince(last.adjustedTime) <= Self.labelStickyInterval {
            return DisplayedTide(event: last, recency: .past)
        }
        if let next {
            return DisplayedTide(event: next, recency: .upcoming)
        }
        if let last {
            return DisplayedTide(event: last, recency: .past)
        }
        return nil
    }

    /// Zeitfenster, in dem die prognostizierte Rohhöhe ≤ „wahrscheinlich“ ist (Schwellwerte aus Einstellungen).
    struct StrandyArcWindow {
        let startTime: Date
        let endTime: Date
        let startClockAngleDeg: Double
        let endClockAngleDeg: Double
    }

    /// Gezeitenhöhe zur Zeit (kosinusförmige Interpolation zwischen benachbarten Extremen).
    func height(at time: Date) -> Double? {
        guard let prev = events.last(where: { $0.adjustedTime <= time }),
              let next = events.first(where: { $0.adjustedTime > time }) else { return nil }
        let total = next.adjustedTime.timeIntervalSince(prev.adjustedTime)
        guard total > 0 else { return prev.height }
        let progress = max(0, min(1, time.timeIntervalSince(prev.adjustedTime) / total))
        let h0 = prev.height, h1 = next.height
        return (h0 + h1) / 2.0 + (h0 - h1) / 2.0 * cos(.pi * progress)
    }

    /// Uhrwinkel (0° = Flut oben, 180° = Ebbe unten) für einen Zeitpunkt.
    func clockAngle(at time: Date) -> Double {
        guard let prev = events.last(where: { $0.adjustedTime <= time }),
              let next = events.first(where: { $0.adjustedTime > time }) else { return 180 }
        let total = next.adjustedTime.timeIntervalSince(prev.adjustedTime)
        guard total > 0 else { return 180 }
        let progress = max(0, min(1, time.timeIntervalSince(prev.adjustedTime) / total))
        if prev.type == .highTide {
            return progress * 180.0
        }
        return 180.0 + progress * 180.0
    }

    private static func formatCountdown(to target: Date, from now: Date) -> String {
        let secs = max(0, target.timeIntervalSince(now))
        let h = Int(secs) / 3600
        let m = Int(secs) % 3600 / 60
        let s = Int(secs) % 60
        return h > 0
            ? String(format: "%dh %02dm", h, m)
            : String(format: "%dm %02ds", m, s)
    }

    // MARK: - Swipe-Seiten (eine Seite pro Ebbe)

    /// Eine swipebare Uhr-Seite — Anker ist immer die Ebbe unten.
    struct TideEbbePage: Identifiable {
        var id: UUID { lowTide.id }
        let lowTide: TideEvent
        let highBefore: TideEvent?
        let highAfter: TideEvent?
    }

    static let pastLowPages = 1
    static let futureLowPages = 5

    /// Ebben im Umfang 1 zurück + 5 voraus (je eine Swipe-Seite).
    var ebbeSwipePages: [TideEbbePage] {
        allowedLowTidesForSwipe().map { low in
            TideEbbePage(
                lowTide: low,
                highBefore: events.last { $0.type == .highTide && $0.adjustedTime < low.adjustedTime },
                highAfter: events.first { $0.type == .highTide && $0.adjustedTime > low.adjustedTime }
            )
        }
    }

    /// Live-Seite: Ebbe laut 3-h-Regel (`displayedLowTide`).
    var activeLiveEbbePageIndex: Int? {
        guard let liveLow = displayedLowTide?.event else { return nil }
        return ebbeSwipePages.firstIndex { $0.lowTide.id == liveLow.id }
    }

    func previewTimeLabel(for event: TideEvent) -> String {
        "\(relativeDayLabel(for: event.adjustedTime)) \(formatHM(event.adjustedTime))"
    }

    func liveTimeLabel(for displayed: DisplayedTide) -> String {
        let prefix = displayed.recency == .past ? "alt" : "neu"
        return "\(prefix) · \(relativeDayLabel(for: displayed.event.adjustedTime)) \(formatHM(displayed.event.adjustedTime))"
    }

    private func formatHM(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TideService.canaryIslandsTimeZone
        return f.string(from: date)
    }

    func relativeDayLabel(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let dayNow = cal.startOfDay(for: now)
        let dayDate = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: dayNow, to: dayDate).day ?? 0
        switch diff {
        case -1: return "Gestern"
        case 0: return "Heute"
        case 1: return "Morgen"
        case 2: return "übermorgen"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.timeZone = TideService.canaryIslandsTimeZone
            f.dateFormat = "E d.M."
            return f.string(from: date)
        }
    }

    func strandyArcWindow(for lowTide: TideEvent) -> StrandyArcWindow? {
        let likely = TideBeachWalk.thresholdLikely
        guard lowTide.height <= likely else { return nil }

        guard let highBefore = events.last(where: { $0.type == .highTide && $0.adjustedTime < lowTide.adjustedTime }),
              let highAfter = events.first(where: { $0.type == .highTide && $0.adjustedTime > lowTide.adjustedTime }) else {
            return nil
        }

        let tStart = crossingOnDecreasingSegment(
            from: highBefore.adjustedTime,
            to: lowTide.adjustedTime,
            threshold: likely
        )
        let tEnd = crossingOnIncreasingSegment(
            from: lowTide.adjustedTime,
            to: highAfter.adjustedTime,
            threshold: likely
        )

        guard tStart <= tEnd else { return nil }

        return StrandyArcWindow(
            startTime: tStart,
            endTime: tEnd,
            startClockAngleDeg: clockAngle(at: tStart),
            endClockAngleDeg: clockAngle(at: tEnd)
        )
    }

    /// Strandy-Bogen für die angezeigte Ebbe (Live-Seite / globale Anzeige).
    var strandyArcWindow: StrandyArcWindow? {
        guard let low = displayedLowTide?.event else { return nil }
        return strandyArcWindow(for: low)
    }

    private func allowedLowTidesForSwipe() -> [TideEvent] {
        let lows = events.filter { $0.type == .lowTide }
        guard !lows.isEmpty else { return [] }
        if let past = lows.last(where: { $0.adjustedTime <= now }) {
            let upcoming = lows.filter { $0.adjustedTime > past.adjustedTime }
            return [past] + Array(upcoming.prefix(Self.futureLowPages))
        }
        return Array(lows.prefix(Self.pastLowPages + Self.futureLowPages))
    }

    /// Erster Zeitpunkt auf fallendem Ast (Flut→Ebbe), an dem Höhe ≤ Schwelle.
    private func crossingOnDecreasingSegment(from tHigh: Date, to tLow: Date, threshold: Double) -> Date {
        guard let hHigh = height(at: tHigh), let hLow = height(at: tLow) else { return tLow }
        if hHigh <= threshold { return tHigh }
        if hLow > threshold { return tLow }
        return binarySearchThreshold(from: tHigh, to: tLow, threshold: threshold, wantBelow: true)
    }

    /// Letzter Zeitpunkt auf steigendem Ast (Ebbe→Flut), an dem Höhe noch ≤ Schwelle.
    private func crossingOnIncreasingSegment(from tLow: Date, to tHigh: Date, threshold: Double) -> Date {
        guard let hLow = height(at: tLow), let hHigh = height(at: tHigh) else { return tHigh }
        if hHigh <= threshold { return tHigh }
        if hLow > threshold { return tLow }
        return binarySearchThreshold(from: tLow, to: tHigh, threshold: threshold, wantBelow: false)
    }

    private func binarySearchThreshold(
        from tStart: Date,
        to tEnd: Date,
        threshold: Double,
        wantBelow: Bool
    ) -> Date {
        var lo = tStart.timeIntervalSince1970
        var hi = tEnd.timeIntervalSince1970
        for _ in 0..<48 {
            let mid = (lo + hi) / 2
            let t = Date(timeIntervalSince1970: mid)
            guard let h = height(at: t) else { break }
            if wantBelow {
                if h <= threshold { hi = mid } else { lo = mid }
            } else if h <= threshold {
                lo = mid
            } else {
                hi = mid
            }
        }
        return Date(timeIntervalSince1970: (lo + hi) / 2)
    }

    var countdownString: String {
        guard let next = nextEvent else { return "" }
        return Self.formatCountdown(to: next.adjustedTime, from: now)
    }

    func countdownString(to event: TideEvent) -> String {
        Self.formatCountdown(to: event.adjustedTime, from: now)
    }
}
