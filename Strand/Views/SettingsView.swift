import SwiftUI

struct SettingsView: View {
    let viewModel: TideViewModel
    @State private var showReloadConfirm = false

    var body: some View {
        NavigationStack {
            Form {
            vorhersageSection
            zeitkorrekturSection
            schriftSection
            strandgangSection
                datenquelleSection
                kiSection
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Vorhersage

    private var vorhersageSection: some View {
        Section {
            LabeledContent("Tabelle", value: "Immer 7 Tage")
            Picker("Standard Diagramm", selection: Binding(
                get: { viewModel.chartDays },
                set: { viewModel.chartDays = $0 }
            )) {
                ForEach(TideViewModel.chartDayOptions, id: \.days) { option in
                    Text(option.label).tag(option.days)
                }
            }
        } header: {
            Text("Vorhersage")
        } footer: {
            Text("Tabelle zeigt immer 7 Tage. Standard-Zeitraum für das Diagramm beim Start.")
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

    // MARK: - Tabelle Schrift

    private var schriftSection: some View {
        Section {
            HStack {
                Text("Schriftgröße")
                Spacer()
                Text(String(format: "%.0f pt", viewModel.tableFontSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { viewModel.tableFontSize },
                    set: { viewModel.tableFontSize = $0 }
                ),
                in: 10...20, step: 1
            ) {
                Text("Schrift")
            } minimumValueLabel: {
                Text("10").font(.caption)
            } maximumValueLabel: {
                Text("20").font(.caption)
            }
            Button("Standard (14 pt)") { viewModel.tableFontSize = 14 }
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
