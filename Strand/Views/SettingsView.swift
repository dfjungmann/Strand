import SwiftUI

struct SettingsView: View {
    let viewModel: TideViewModel
    @State private var showReloadConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                vorhersageSection
                zeitkorrekturSection
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
            Picker("Tage im Voraus", selection: Binding(
                get: { viewModel.selectedDays },
                set: { newValue in
                    viewModel.selectedDays = newValue
                    Task { await viewModel.reload() }
                }
            )) {
                ForEach(TideViewModel.availableDays, id: \.self) { days in
                    Text("\(days) Tage").tag(days)
                }
            }
        } header: {
            Text("Vorhersage")
        } footer: {
            Text("Wie viele Tage ab heute werden geladen.")
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

    // MARK: - Strandgang

    private var strandgangSection: some View {
        Section {
            HStack {
                Text("Grenzwert Niedrigwasser")
                Spacer()
                Text(String(format: "%.2f m", viewModel.beachWalkThreshold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { viewModel.beachWalkThreshold },
                    set: { viewModel.beachWalkThreshold = $0 }
                ),
                in: 0.1...1.5,
                step: 0.05
            ) {
                Text("Grenzwert")
            } minimumValueLabel: {
                Text("0.1 m").font(.caption)
            } maximumValueLabel: {
                Text("1.5 m").font(.caption)
            }

            Button("Auf Standard zurücksetzen (0.60 m)") {
                viewModel.beachWalkThreshold = 0.6
            }
            .foregroundStyle(.blue)
        } header: {
            Text("Strandspaziergang")
        } footer: {
            Text("Strandgang möglich wenn das Niedrigwasser diese Höhe unterschreitet. Vor Ort kalibrierbar.")
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

            Button {
                Task { await viewModel.reload() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Daten neu laden")
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
