import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    let viewModel: TideViewModel

    // MARK: - AppStorage

    @AppStorage("notif_enabled")          private var notifEnabled = false
    @AppStorage("notif_window_start")     private var windowStart = 7
    @AppStorage("notif_window_end")       private var windowEnd = 22
    @AppStorage("notif_content_start")    private var contentStart = 6
    @AppStorage("notif_content_end")      private var contentEnd = 22
    @AppStorage("notif_daily_enabled")    private var dailyEnabled = false
    @AppStorage("notif_daily_hour")       private var dailyHour = 8
    @AppStorage("notif_daily_minute")     private var dailyMinute = 0
    @AppStorage("notif_daily_low_today")  private var dailyLowToday = true
    @AppStorage("notif_daily_walk_today") private var dailyWalkToday = true
    @AppStorage("notif_daily_low_tomorrow")   private var dailyLowTomorrow = true
    @AppStorage("notif_daily_walk_tomorrow")  private var dailyWalkTomorrow = true
    @AppStorage("notif_daily_low2_tomorrow")  private var dailyLow2Tomorrow = false
    @AppStorage("notif_daily_walk2_tomorrow") private var dailyWalk2Tomorrow = false
    @AppStorage("notif_daily_water_temp") private var dailyWaterTemp = true
    @AppStorage("notif_daily_moon")       private var dailyMoon = true
    @AppStorage("notif_prewalk_enabled")  private var prewalkEnabled = false
    @AppStorage("notif_prewalk_hours")    private var prewalkHours = 1
    @AppStorage("notif_at_tide_enabled")  private var atTideEnabled = false

    // MARK: - State

    @State private var pendingNotifications: [UNNotificationRequest] = []
    @State private var isLoadingPending = false
    @State private var isRescheduling = false
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var testSent = false
    @State private var selectedNotification: UNNotificationRequest? = nil

    // Derived Date binding for daily time picker
    private var dailyTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = dailyHour
                comps.minute = dailyMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                dailyHour = comps.hour ?? 8
                dailyMinute = comps.minute ?? 0
            }
        )
    }

    /// Single value that changes when any relevant setting changes — used to trigger rescheduling.
    private var settingsFingerprint: String {
        "\(notifEnabled)\(windowStart)\(windowEnd)\(contentStart)\(contentEnd)" +
        "\(dailyEnabled)\(dailyHour)\(dailyMinute)" +
        "\(dailyLowToday)\(dailyWalkToday)\(dailyLowTomorrow)\(dailyWalkTomorrow)" +
        "\(dailyLow2Tomorrow)\(dailyWalk2Tomorrow)" +
        "\(dailyWaterTemp)\(dailyMoon)\(prewalkEnabled)\(prewalkHours)\(atTideEnabled)"
    }

    var body: some View {
        Form {
            testSection
            masterSection
            windowSection.disabled(!notifEnabled)
            contentWindowSection.disabled(!notifEnabled)
            dailySection.disabled(!notifEnabled)
            prewalkSection.disabled(!notifEnabled)
            pendingSection
        }
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadAuthStatus() }
        .task { await loadPending() }
        .onChange(of: settingsFingerprint) { _, _ in
            Task { await applyChanges() }
        }
        .sheet(item: $selectedNotification) { req in
            NotificationDetailView(request: req)
        }
    }

    // MARK: - Sections

    private var testSection: some View {
        Section {
            Button {
                Task {
                    await NotificationManager.shared.sendTestNotification(viewModel: viewModel)
                    testSent = true
                    try? await Task.sleep(for: .seconds(3))
                    testSent = false
                }
            } label: {
                Label(
                    testSent ? "✓ Nachricht in 5 Sek." : "Testnachricht senden (5 Sek.)",
                    systemImage: testSent ? "checkmark.circle.fill" : "bell.badge"
                )
                .foregroundStyle(testSent ? .green : .accentColor)
            }
            .disabled(testSent)
        } header: {
            Text("Test")
        } footer: {
            // iOS zeigt Notifications nur an, wenn die App im Hintergrund läuft oder das Gerät gesperrt ist.
            Text("Die Notification erscheint, sobald die App in den Hintergrund wechselt oder das Gerät gesperrt wird.")
        }
    }

    private var masterSection: some View {
        Section {
            Toggle("Benachrichtigungen", isOn: $notifEnabled)
                .onChange(of: notifEnabled) { _, newValue in
                    if newValue {
                        Task {
                            let granted = await NotificationManager.shared.requestPermission()
                            if !granted {
                                notifEnabled = false
                            }
                            await loadAuthStatus()
                        }
                    }
                }
            if authStatus == .denied {
                Label {
                    Text("Benachrichtigungen in den Systemeinstellungen deaktiviert")
                        .font(.caption)
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Master")
        } footer: {
            Text("Aktiviert oder deaktiviert alle Strand-Benachrichtigungen.")
        }
    }

    private var windowSection: some View {
        Section {
            HStack {
                Text("Erlaubt von")
                Spacer()
                Stepper(String(format: "%02d:00", windowStart), value: $windowStart, in: 0...(windowEnd - 1))
                    .fixedSize()
            }
            HStack {
                Text("Erlaubt bis")
                Spacer()
                Stepper(String(format: "%02d:00", windowEnd), value: $windowEnd, in: (windowStart + 1)...23)
                    .fixedSize()
            }
        } header: {
            Text("Zeitfenster")
        } footer: {
            Text(String(format: "Benachrichtigungen nur zwischen %02d:00 und %02d:00 Uhr senden.", windowStart, windowEnd))
        }
    }

    private var contentWindowSection: some View {
        Section {
            HStack {
                Text("Strandgang ab")
                Spacer()
                Stepper(String(format: "%02d:00", contentStart), value: $contentStart, in: 0...(contentEnd - 1))
                    .fixedSize()
            }
            HStack {
                Text("Strandgang bis")
                Spacer()
                Stepper(String(format: "%02d:00", contentEnd), value: $contentEnd, in: (contentStart + 1)...23)
                    .fixedSize()
            }
        } header: {
            Text("Strandgang-Fenster")
        } footer: {
            Text(String(format: "Nur Strandspaziergänge zwischen %02d:00 und %02d:00 Uhr werden in der Meldung erwähnt. Tiefstände außerhalb werden mit 🌙 markiert.", contentStart, contentEnd))
        }
    }

    private var dailySection: some View {
        Section {
            Toggle("Tägliche Statusmeldung", isOn: $dailyEnabled)

            DatePicker(
                "Uhrzeit",
                selection: dailyTimeBinding,
                displayedComponents: [.hourAndMinute]
            )
            .disabled(!dailyEnabled)

            if dailyEnabled {
                Toggle("Nächster Tiefstand heute", isOn: $dailyLowToday)
                Toggle("Strandgang heute", isOn: $dailyWalkToday)
                Toggle("Nächster Tiefstand morgen", isOn: $dailyLowTomorrow)
                Toggle("Strandgang morgen", isOn: $dailyWalkTomorrow)
                Toggle("Zweiter Tiefstand morgen", isOn: $dailyLow2Tomorrow)
                Toggle("Strandgang zweiter Tiefstand morgen", isOn: $dailyWalk2Tomorrow)
                Toggle("Wassertemperatur", isOn: $dailyWaterTemp)
                Toggle("Nächster Voll-/Neumond", isOn: $dailyMoon)
            }
        } header: {
            Text("Tägliche Statusmeldung")
        } footer: {
            Text("Jeden Tag eine Zusammenfassung der Gezeiten und Strandgang-Möglichkeiten.")
        }
    }

    private var prewalkSection: some View {
        Section {
            Toggle("Warnung vor Strandgang", isOn: $prewalkEnabled)
            if prewalkEnabled {
                Stepper(value: $prewalkHours, in: 1...3) {
                    HStack {
                        Text("Stunden vorher")
                        Spacer()
                        Text("\(prewalkHours) Std.")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            Toggle("Meldung zur Ebbe-Uhrzeit", isOn: $atTideEnabled)
        } header: {
            Text("Vorab-Warnung")
        } footer: {
            Text("Vorab: X Stunden vor der Ebbe. Zur Uhrzeit: direkt wenn die Ebbe erreicht ist (nur bei möglichem Strandgang, Ebbe ≤ 0.9 m).")
        }
    }

    private var pendingSection: some View {
        Section {
            if isLoadingPending || isRescheduling {
                HStack {
                    ProgressView()
                    Text(isRescheduling ? "Generiere…" : "Lade…")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            Button {
                Task { await loadPending() }
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }

            if pendingNotifications.isEmpty && !isLoadingPending {
                Text("Keine geplanten Benachrichtigungen")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(pendingNotifications, id: \.identifier) { req in
                    Button {
                        selectedNotification = req
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notificationDateLabel(req))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(req.content.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if !req.content.body.isEmpty {
                                Text(req.content.body.components(separatedBy: "\n").first ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { pendingNotifications[$0].identifier }
                    NotificationManager.shared.remove(ids: ids)
                    pendingNotifications.remove(atOffsets: indexSet)
                }
            }

            Button(role: .destructive) {
                NotificationManager.shared.removeAll()
                pendingNotifications = []
            } label: {
                Label("Alle löschen", systemImage: "trash")
            }

            Button {
                Task {
                    isRescheduling = true
                    await NotificationManager.shared.reschedule(viewModel: viewModel)
                    await loadPending()
                    isRescheduling = false
                }
            } label: {
                Label("Neu generieren", systemImage: "sparkles")
            }
        } header: {
            Text("Geplante Meldungen (\(pendingNotifications.count))")
        }
    }

    // MARK: - Helpers

    private func applyChanges() async {
        await NotificationManager.shared.reschedule(viewModel: viewModel)
        await loadPending()
    }

    private func loadPending() async {
        isLoadingPending = true
        let all = await NotificationManager.shared.pendingNotifications()
        pendingNotifications = all.sorted { lhs, rhs in
            fireDate(lhs) < fireDate(rhs)
        }
        isLoadingPending = false
    }

    private func loadAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    private func fireDate(_ request: UNNotificationRequest) -> Date {
        if let calTrigger = request.trigger as? UNCalendarNotificationTrigger {
            return calTrigger.nextTriggerDate() ?? .distantFuture
        }
        if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
            return intervalTrigger.nextTriggerDate() ?? .distantFuture
        }
        return .distantFuture
    }

    private func notificationDateLabel(_ request: UNNotificationRequest) -> String {
        let date = fireDate(request)
        if date == .distantFuture { return request.identifier }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        fmt.locale = Locale(identifier: "de_DE")
        return fmt.string(from: date)
    }
}

// MARK: - UNNotificationRequest Identifiable

extension UNNotificationRequest: @retroactive Identifiable {
    public var id: String { identifier }
}

// MARK: - Notification Detail Sheet

struct NotificationDetailView: View {
    let request: UNNotificationRequest
    @Environment(\.dismiss) private var dismiss

    private var fireDate: Date? {
        if let t = request.trigger as? UNCalendarNotificationTrigger { return t.nextTriggerDate() }
        if let t = request.trigger as? UNTimeIntervalNotificationTrigger { return t.nextTriggerDate() }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Geplant für") {
                    if let date = fireDate {
                        Text(date, style: .date)
                        Text(date, style: .time)
                    } else {
                        Text(request.identifier).foregroundStyle(.secondary)
                    }
                }

                Section("Titel") {
                    Text(request.content.title)
                        .font(.headline)
                }

                if !request.content.body.isEmpty {
                    Section("Inhalt") {
                        Text(request.content.body)
                            .font(.body)
                            .lineSpacing(4)
                    }
                }
            }
            .navigationTitle("Meldung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}
