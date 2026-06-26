import SwiftUI

struct SettingsView: View {
    let viewModel: TideViewModel
    @State private var showReloadConfirm = false

    var body: some View {
        NavigationStack {
            Form {
            zeitkorrekturSection
            schriftSection
            strandgangSection
                datenquelleSection
                verlaufSection
                radarSection
                kiSection
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Zeitkorrektur

    private var zeitkorrekturSection: some View {
        Section {
            HStack {
                Text("Zeitverschiebung")
                Spacer()
                Text("\(viewModel.timeOffsetMinutes > 0 ? "+" : "")\(viewModel.timeOffsetMinutes) Min.")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Stepper(
                value: Binding(
                    get: { viewModel.timeOffsetMinutes },
                    set: { viewModel.timeOffsetMinutes = $0 }
                ),
                in: -60...60,
                step: 5
            ) {
                EmptyView()
            }

            Button("Auf Standard zurücksetzen (−15 Min.)") {
                viewModel.timeOffsetMinutes = -15
            }
            .foregroundStyle(.blue)
        } header: {
            Text("Zeitkorrektur")
        } footer: {
            Text("Korrektur von Puerto de la Luz auf Playa del Aguila. Negativ = früher.")
        }
    }

    @AppStorage("tableFontSize") private var tableFontSize = 14.0
    @AppStorage("verlauf_default_days") private var verlaufDefaultDays: Int = 5

    // MARK: - Tabelle Schrift

    private var schriftSection: some View {
        Section {
            HStack {
                Text("Schriftgröße")
                Spacer()
                Text(String(format: "%.0f pt", tableFontSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $tableFontSize, in: 10...25, step: 1) {
                Text("Schrift")
            } minimumValueLabel: {
                Text("10").font(.caption)
            } maximumValueLabel: {
                Text("25").font(.caption)
            }
            Button("Standard (14 pt)") { tableFontSize = 14 }
                .foregroundStyle(.blue)
        } header: {
            Text("Tabelle – Schriftgröße")
        } footer: {
            Text("Schriftgröße der Zeiten und Höhen in der Gezeitentabelle.")
        }
    }

    // MARK: - Strandgang

    private var strandgangSection: some View {
        Section {
            // Sicher (grün)
            HStack {
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("Sicher")
                Spacer()
                Text(String(format: "%.2f m", viewModel.beachWalkThresholdSafe))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { viewModel.beachWalkThresholdSafe },
                    set: {
                        viewModel.beachWalkThresholdSafe = $0
                        if viewModel.beachWalkThresholdLikely < $0 {
                            viewModel.beachWalkThresholdLikely = $0
                        }
                    }
                ),
                in: 0.1...1.5, step: 0.05
            ) {} minimumValueLabel: { Text("0.1").font(.caption) }
               maximumValueLabel: { Text("1.5").font(.caption) }

            // Wahrscheinlich (gelb)
            HStack {
                Circle().fill(.yellow).frame(width: 10, height: 10)
                Text("Wahrscheinlich")
                Spacer()
                Text(String(format: "%.2f m", viewModel.beachWalkThresholdLikely))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { viewModel.beachWalkThresholdLikely },
                    set: {
                        viewModel.beachWalkThresholdLikely = max($0, viewModel.beachWalkThresholdSafe)
                    }
                ),
                in: 0.1...1.5, step: 0.05
            ) {} minimumValueLabel: { Text("0.1").font(.caption) }
               maximumValueLabel: { Text("1.5").font(.caption) }

            Button("Standard zurücksetzen (0.60 / 0.90 m)") {
                viewModel.beachWalkThresholdSafe   = 0.6
                viewModel.beachWalkThresholdLikely = 0.9
            }
            .foregroundStyle(.blue)
        } header: {
            Text("Strandspaziergang")
        } footer: {
            Text("🟢 Sicher: Niedrigwasser unter diesem Wert = grün.\n🟡 Wahrscheinlich: zwischen Sicher und diesem Wert = gelb.\nVor Ort kalibrierbar.")
        }
    }

    // MARK: - Datenquelle

    private var datenquelleSection: some View {
        Section("Datenquelle") {
            LabeledContent("Station", value: "Puerto de la Luz (Gran Canaria)")
            LabeledContent("Stations-ID", value: "56")
            LabeledContent("Quelle", value: "Instituto Hidrográfico de la Marina")
            if let date = viewModel.lastUpdated {
                LabeledContent("Zuletzt geladen") {
                    Text(date, style: .time)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Gecachte Tage") {
                Text("\(viewModel.cachedDayCount)")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.reload() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Fehlende Tage nachladen")
                }
            }

            Button(role: .destructive) {
                Task { await viewModel.clearCache() }
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Cache leeren und neu laden")
                }
            }
        }
    }

    // MARK: - Verlauf

    private var verlaufSection: some View {
        Section {
            Stepper(value: $verlaufDefaultDays, in: 2...14) {
                HStack {
                    Text("Standard-Tage")
                    Spacer()
                    Text("\(verlaufDefaultDays) Tage")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Verlauf")
        } footer: {
            Text("Anzahl der Tage die beim Öffnen des Verlauf-Tabs angezeigt werden (2–14).")
        }
    }

    // MARK: - Radar API Key

    private var radarSection: some View {
        Section {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wetterradar")
                        .font(.subheadline)
                    let key = UserDefaults.standard.string(forKey: "owm_api_key") ?? ""
                    if key.isEmpty {
                        Text("API-Key nicht konfiguriert")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("API-Key gespeichert ✓")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            }
            NavigationLink("OpenWeatherMap konfigurieren") {
                OWMSettingsView()
            }
        } header: {
            Text("Radar")
        } footer: {
            Text("Kostenloser API-Key von openweathermap.org für schnelle native Radar-Kacheln.")
        }
    }

    // MARK: - KI

    private var kiSection: some View {
        Section {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KI-Assistent")
                        .font(.subheadline)
                    Text("OpenAI-Zugangsdaten noch nicht konfiguriert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink("OpenAI konfigurieren") {
                OpenAISettingsView()
            }
        } header: {
            Text("Künstliche Intelligenz")
        } footer: {
            Text("OpenAI API-Schlüssel für KI-gestützte Strandprognosen. Zugangsdaten werden sicher im Keychain gespeichert.")
        }
    }
}

// MARK: - OWM Settings

struct OWMSettingsView: View {
    @AppStorage("owm_api_key") private var apiKey = ""
    @State private var tempKey = ""
    @State private var showKey = true          // visible by default so user can verify
    @State private var testStatus: TestStatus = .idle

    enum TestStatus {
        case idle, testing
        case ok(Int)     // HTTP 200
        case fail(Int)   // other HTTP code
        case error(String)

        var label: String {
            switch self {
            case .idle:        return ""
            case .testing:     return "Teste…"
            case .ok:          return "✅ Map-Tiles funktionieren"
            case .fail(let c): return "❌ HTTP \(c) – Key hat keinen Map-Zugriff"
            case .error(let m): return "❌ \(m)"
            }
        }
        var color: Color {
            switch self {
            case .ok:          return .green
            case .fail, .error: return .red
            default:           return .secondary
            }
        }
    }

    private var trimmed: String { tempKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                HStack {
                    if showKey {
                        TextField("API-Key eingeben…", text: $tempKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("API-Key eingeben…", text: $tempKey)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Speichern") {
                    apiKey = trimmed
                    testStatus = .idle
                }
                .disabled(trimmed.isEmpty || trimmed == apiKey)

                Button("Map-Tile testen") {
                    Task { await testKey() }
                }
                .disabled(trimmed.isEmpty)

                if testStatus.label != "" {
                    Text(testStatus.label)
                        .font(.caption)
                        .foregroundStyle(testStatus.color)
                }
            } header: {
                Text("OpenWeatherMap API-Key")
            } footer: {
                Text("Key unter openweathermap.org → \"My API Keys\" kopieren.")
            }

            if !apiKey.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Key gespeichert (\(apiKey.prefix(6))…\(apiKey.suffix(4)))")
                            .font(.caption)
                    }
                    Button("Key löschen", role: .destructive) { apiKey = ""; tempKey = ""; testStatus = .idle }
                }
            }
        }
        .navigationTitle("OpenWeatherMap")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tempKey = apiKey }
    }

    private func testKey() async {
        testStatus = .testing
        // Test with a known tile (zoom 5, x=16, y=11 = Europe/Atlantic)
        let urlStr = "https://tile.openweathermap.org/map/clouds_new/5/16/11.png?appid=\(trimmed)"
        guard let url = URL(string: urlStr) else { testStatus = .error("Ungültige URL"); return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            testStatus = code == 200 ? .ok(code) : .fail(code)
        } catch {
            testStatus = .error(error.localizedDescription)
        }
    }
}

// MARK: - OpenAI Placeholder

struct OpenAISettingsView: View {
    @AppStorage("openai_api_key") private var apiKey = ""
    @State private var tempKey = ""
    @State private var showKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    if showKey {
                        TextField("sk-...", text: $tempKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("sk-...", text: $tempKey)
                    }
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("API-Schlüssel speichern") {
                    apiKey = tempKey
                }
                .disabled(tempKey.isEmpty)
            } header: {
                Text("OpenAI API-Schlüssel")
            } footer: {
                Text("Den Schlüssel erhältst du unter platform.openai.com. Er wird nur lokal auf deinem Gerät gespeichert.")
            }

            if !apiKey.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API-Schlüssel gespeichert")
                    }
                    Button("Schlüssel löschen", role: .destructive) {
                        apiKey = ""
                        tempKey = ""
                    }
                }
            }
        }
        .navigationTitle("OpenAI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tempKey = apiKey }
    }
}
