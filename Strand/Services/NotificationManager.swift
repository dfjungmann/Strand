import UserNotifications
import Foundation

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - AppStorage Keys (read via UserDefaults directly since @MainActor class can't use @AppStorage)

    private var isEnabled: Bool          { UserDefaults.standard.bool(forKey: "notif_enabled") }
    private var windowStart: Int         { let v = UserDefaults.standard.object(forKey: "notif_window_start") as? Int; return v ?? 7 }
    private var windowEnd: Int           { let v = UserDefaults.standard.object(forKey: "notif_window_end") as? Int; return v ?? 22 }
    private var contentStart: Int        { let v = UserDefaults.standard.object(forKey: "notif_content_start") as? Int; return v ?? 6 }
    private var contentEnd: Int          { let v = UserDefaults.standard.object(forKey: "notif_content_end") as? Int; return v ?? 22 }
    private var dailyEnabled: Bool       { UserDefaults.standard.bool(forKey: "notif_daily_enabled") }
    private var dailyHour: Int           { let v = UserDefaults.standard.object(forKey: "notif_daily_hour") as? Int; return v ?? 8 }
    private var dailyMinute: Int         { let v = UserDefaults.standard.object(forKey: "notif_daily_minute") as? Int; return v ?? 0 }
    private var dailyLowToday: Bool      { let v = UserDefaults.standard.object(forKey: "notif_daily_low_today") as? Bool; return v ?? true }
    private var dailyWalkToday: Bool     { let v = UserDefaults.standard.object(forKey: "notif_daily_walk_today") as? Bool; return v ?? true }
    private var dailyLowTomorrow: Bool   { let v = UserDefaults.standard.object(forKey: "notif_daily_low_tomorrow") as? Bool; return v ?? true }
    private var dailyWalkTomorrow: Bool  { let v = UserDefaults.standard.object(forKey: "notif_daily_walk_tomorrow") as? Bool; return v ?? true }
    private var dailyLow2Tomorrow: Bool  { let v = UserDefaults.standard.object(forKey: "notif_daily_low2_tomorrow") as? Bool; return v ?? false }
    private var dailyWalk2Tomorrow: Bool { let v = UserDefaults.standard.object(forKey: "notif_daily_walk2_tomorrow") as? Bool; return v ?? false }
    private var dailyWaterTemp: Bool     { let v = UserDefaults.standard.object(forKey: "notif_daily_water_temp") as? Bool; return v ?? true }
    private var dailyMoon: Bool          { let v = UserDefaults.standard.object(forKey: "notif_daily_moon") as? Bool; return v ?? true }
    private var prewalkEnabled: Bool     { UserDefaults.standard.bool(forKey: "notif_prewalk_enabled") }
    private var prewalkHours: Int        { let v = UserDefaults.standard.object(forKey: "notif_prewalk_hours") as? Int; return v ?? 1 }
    private var atTideEnabled: Bool      { UserDefaults.standard.bool(forKey: "notif_at_tide_enabled") }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Reschedule

    func reschedule(viewModel: TideViewModel) async {
        let center = UNUserNotificationCenter.current()

        guard isEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        // Remove only managed identifiers (daily_ and prewalk_) before adding new ones
        let pending = await center.pendingNotificationRequests()
        let managedIDs = pending.map(\.identifier).filter {
            $0.hasPrefix("daily_") || $0.hasPrefix("prewalk_")
        }
        center.removePendingNotificationRequests(withIdentifiers: managedIDs)

        var requests: [UNNotificationRequest] = []

        if dailyEnabled {
            requests += buildDailyNotifications(viewModel: viewModel)
        }

        if prewalkEnabled {
            requests += buildPrewalkNotifications(viewModel: viewModel)
        }

        if atTideEnabled {
            requests += buildAtTideNotifications(viewModel: viewModel)
        }

        for request in requests {
            try? await center.add(request)
        }
    }

    // MARK: - Pending / Remove

    func pendingNotifications() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func remove(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Daily Notifications

    private func buildDailyNotifications(viewModel: TideViewModel) -> [UNNotificationRequest] {
        guard (windowStart...windowEnd).contains(dailyHour) else { return [] }

        let canary = TideService.canaryIslandsTimeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = canary
        let today = cal.startOfDay(for: Date())

        var requests: [UNNotificationRequest] = []

        for dayOffset in 0..<7 {
            guard let targetDate = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            let dateStr = isoDateString(targetDate, calendar: cal)
            let identifier = "daily_\(dateStr)"

            var components = cal.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = dailyHour
            components.minute = dailyMinute
            components.second = 0

            guard let fireDate = cal.date(from: components),
                  fireDate > Date() else { continue }

            let body = buildDailyBody(for: targetDate, viewModel: viewModel, calendar: cal)
            guard !body.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = "🏖️ Strand · Playa del Aguila"
            content.body = body
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }

        return requests
    }

    private func buildDailyBody(for date: Date, viewModel: TideViewModel, calendar cal: Calendar) -> String {
        let canary = TideService.canaryIslandsTimeZone
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.timeZone = canary

        var calCanary = Calendar(identifier: .gregorian)
        calCanary.timeZone = canary

        let todayStart = cal.startOfDay(for: date)
        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart) else { return "" }

        let todayDay    = viewModel.tideDays.first { cal.startOfDay(for: $0.date) == todayStart }
        let tomorrowDay = viewModel.tideDays.first { cal.startOfDay(for: $0.date) == tomorrowStart }

        func isInContentWindow(_ event: TideEvent) -> Bool {
            let hour = calCanary.component(.hour, from: event.adjustedTime)
            return hour >= contentStart && hour < contentEnd
        }

        // Farbiger Kreis + Spaziergänger je nach Strandgang-Status (iOS Notifications = nur Text/Emoji)
        func statusEmoji(_ event: TideEvent) -> String {
            guard isInContentWindow(event) else { return "🌙" }
            switch event.beachWalkStatus {
            case .safe:   return "👣🟢"
            case .likely: return "👣🟡"
            case .none:   return ""
            }
        }

        func formatLow(_ event: TideEvent, showWalk: Bool, showTime: Bool) -> String? {
            guard showTime || showWalk else { return nil }
            let emoji = showWalk ? statusEmoji(event) : (isInContentWindow(event) ? "" : "🌙")
            let timeStr = timeFmt.string(from: event.adjustedTime)
            let heightStr = String(format: "%.1f", event.height)
            if emoji.isEmpty {
                return "\(timeStr) (\(heightStr)m)"
            } else {
                return "\(emoji) \(timeStr) (\(heightStr)m)"
            }
        }

        // Heute: alle Tiefstände chronologisch
        let lowsToday = (todayDay?.events ?? [])
            .filter { $0.type == .lowTide }
            .sorted { $0.adjustedTime < $1.adjustedTime }

        var todayParts: [String] = []
        for low in lowsToday {
            if let s = formatLow(low, showWalk: dailyWalkToday, showTime: dailyLowToday) {
                todayParts.append(s)
            }
        }

        // Morgen: Tiefstände chronologisch, max. 2 je nach Einstellung
        let lowsTomorrow = (tomorrowDay?.events ?? [])
            .filter { $0.type == .lowTide }
            .sorted { $0.adjustedTime < $1.adjustedTime }

        var tomorrowParts: [String] = []
        if let first = lowsTomorrow.first,
           let s = formatLow(first, showWalk: dailyWalkTomorrow, showTime: dailyLowTomorrow) {
            tomorrowParts.append(s)
        }
        if lowsTomorrow.count >= 2,
           let second = lowsTomorrow.dropFirst().first,
           let s = formatLow(second, showWalk: dailyWalk2Tomorrow, showTime: dailyLow2Tomorrow) {
            tomorrowParts.append(s)
        }

        // Zeilen zusammenbauen
        var allLines: [String] = []

        if !todayParts.isEmpty {
            allLines.append("Heute: " + todayParts.joined(separator: " · "))
        }

        var line2Parts: [String] = []
        if dailyWaterTemp, let temp = viewModel.meanWaterTemp(for: date) {
            line2Parts.append("🌊 \(String(format: "%.1f", temp))°C")
        }
        if dailyMoon, let moonLine = nextMoonEventLine(from: date) {
            line2Parts.append(moonLine)
        }
        if !line2Parts.isEmpty {
            allLines.append(line2Parts.joined(separator: " · "))
        }

        if !tomorrowParts.isEmpty {
            allLines.append("Morgen: " + tomorrowParts.joined(separator: " · "))
        }

        return allLines.joined(separator: "\n")
    }

    private func nextMoonEventLine(from startDate: Date) -> String? {
        var dateFmt = DateFormatter()
        dateFmt.dateFormat = "dd.MM."

        for offset in 1...37 {
            guard let checkDate = Calendar.current.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let astro = AstronomyService.data(for: checkDate)
            switch astro.moonPhase {
            case .fullMoon:
                return "🌕 Vollmond: \(dateFmt.string(from: checkDate))"
            case .newMoon:
                return "🌑 Neumond: \(dateFmt.string(from: checkDate))"
            default:
                break
            }
        }
        return nil
    }

    // MARK: - Pre-Walk Notifications

    private func walkEvents(viewModel: TideViewModel) -> [TideEvent] {
        viewModel.tideDays.flatMap(\.events).filter { $0.beachWalkStatus != .none }
    }

    private func walkStatusEmoji(_ event: TideEvent) -> String {
        event.beachWalkStatus == .safe ? "👣🟢" : "👣🟡"
    }

    private func buildPrewalkNotifications(viewModel: TideViewModel) -> [UNNotificationRequest] {
        let canary = TideService.canaryIslandsTimeZone
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.timeZone = canary

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = canary

        let now = Date()
        let cutoff = cal.date(byAdding: .day, value: 10, to: now) ?? now
        let hoursAhead = TimeInterval(prewalkHours) * 3600
        var requests: [UNNotificationRequest] = []

        for event in walkEvents(viewModel: viewModel) {
            let triggerDate = event.adjustedTime.addingTimeInterval(-hoursAhead)
            guard triggerDate > now, triggerDate < cutoff else { continue }
            let triggerHour = cal.component(.hour, from: triggerDate)
            guard triggerHour >= windowStart, triggerHour < windowEnd else { continue }

            let hoursText = prewalkHours == 1 ? "1 Stunde" : "\(prewalkHours) Stunden"
            let content = UNMutableNotificationContent()
            content.title = "🏖️ Strandgang in \(hoursText)"
            content.body = "\(walkStatusEmoji(event)) \(timeFmt.string(from: event.adjustedTime)) (\(String(format: "%.1f", event.height))m)"
            content.sound = .default

            let interval = triggerDate.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            requests.append(UNNotificationRequest(
                identifier: "prewalk_\(Int(event.adjustedTime.timeIntervalSince1970))",
                content: content, trigger: trigger))
        }
        return requests
    }

    private func buildAtTideNotifications(viewModel: TideViewModel) -> [UNNotificationRequest] {
        let canary = TideService.canaryIslandsTimeZone
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.timeZone = canary

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = canary

        let now = Date()
        let cutoff = cal.date(byAdding: .day, value: 10, to: now) ?? now
        var requests: [UNNotificationRequest] = []

        for event in walkEvents(viewModel: viewModel) {
            let triggerDate = event.adjustedTime
            guard triggerDate > now, triggerDate < cutoff else { continue }
            let triggerHour = cal.component(.hour, from: triggerDate)
            guard triggerHour >= windowStart, triggerHour < windowEnd else { continue }

            let content = UNMutableNotificationContent()
            content.title = "🏖️ Jetzt Strandgang möglich"
            content.body = "\(walkStatusEmoji(event)) \(timeFmt.string(from: event.adjustedTime)) (\(String(format: "%.1f", event.height))m)"
            content.sound = .default

            let interval = triggerDate.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            requests.append(UNNotificationRequest(
                identifier: "attide_\(Int(event.adjustedTime.timeIntervalSince1970))",
                content: content, trigger: trigger))
        }
        return requests
    }

    // MARK: - Test Notification

    func sendTestNotification(viewModel: TideViewModel) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["test_notification"])

        let canary = TideService.canaryIslandsTimeZone
        var timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.timeZone = canary

        let now = Date()
        var bodyParts: [String] = []

        let nextLow = viewModel.tideDays
            .compactMap { $0.lowestTide }
            .filter { $0.adjustedTime > now }
            .min(by: { $0.adjustedTime < $1.adjustedTime })

        if let low = nextLow {
            bodyParts.append("Ebbe um \(timeFmt.string(from: low.adjustedTime)) (\(String(format: "%.1f", low.height))m)")
        }

        if let temp = viewModel.meanWaterTemp(for: now) {
            bodyParts.append("\(String(format: "%.1f", temp))°C")
        }

        let content = UNMutableNotificationContent()
        content.title = "🧪 Strand Test"
        content.body = bodyParts.isEmpty
            ? "Testdaten: Ebbe um 14:30 (0.4m) · 22.1°C"
            : bodyParts.joined(separator: " · ")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test_notification", content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Helpers

    private func isoDateString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
