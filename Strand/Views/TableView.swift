import SwiftUI

struct TableView: View {
    let viewModel: TideViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.tideDays.isEmpty {
                    emptyView
                } else {
                    tideList
                }
            }
            .navigationTitle("Gezeiten")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    refreshButton
                }
            }
        }
    }

    // MARK: - List

    private var tideList: some View {
        List {
            ForEach(viewModel.tideDays) { day in
                CompactDayRow(day: day, viewModel: viewModel)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Puerto de la Luz\(offsetDescription) · Kanarische Zeit")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    private var offsetDescription: String {
        let offset = viewModel.timeOffsetMinutes
        guard offset != 0 else { return "" }
        return offset < 0 ? " −\(abs(offset)) Min." : " +\(offset) Min."
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Lade Gezeitendaten…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "Keine Daten",
            systemImage: "wave.3.right",
            description: Text(viewModel.errorMessage ?? "Tippe auf Aktualisieren")
        )
    }

    private var refreshButton: some View {
        Button { Task { await viewModel.reload() } } label: {
            Image(systemName: "arrow.clockwise")
        }
    }
}

// MARK: - Compact Day Row

struct CompactDayRow: View {
    let day: TideDay
    let viewModel: TideViewModel

    private var astronomy: AstronomyData {
        AstronomyService.data(for: day.date)
    }

    private func precipColor(_ prob: Int) -> Color {
        switch prob {
        case 0..<20:  return .green
        case 20..<50: return .orange
        default:      return .blue
        }
    }

    private func cloudIcon(_ cover: Int) -> String {
        switch cover {
        case 0..<20:  return "sun.max.fill"
        case 20..<50: return "cloud.sun.fill"
        case 50..<80: return "cloud.fill"
        default:      return "cloud.heavyrain.fill"
        }
    }

    private func cloudLabel(_ cover: Int) -> String {
        switch cover {
        case 0..<20:  return "sonnig"
        case 20..<50: return "teils bewölkt"
        case 50..<80: return "bewölkt"
        default:      return "stark bewölkt"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {

            // ── Tag-Header ──
            HStack {
                Text(viewModel.formatDayHeader(day.date))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if day.hasBeachWalkOpportunity {
                    HStack(spacing: 3) {
                        Image(systemName: "figure.walk")
                        Text("Strandgang")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                }
            }

            // ── Spalten: Zeit + Höhe übereinander, Strandgang farbig ──
            let fontSize = viewModel.tableFontSize
            HStack(spacing: 4) {
                ForEach(day.events) { event in
                    let tideColor: Color = event.type == .highTide ? .blue : .orange
                    let bgColor: Color = {
                        switch event.beachWalkStatus {
                        case .safe:   return .green
                        case .likely: return .yellow
                        case .none:   return .clear
                        }
                    }()
                    let onBg = event.beachWalkStatus != .none
                    let textOnBg: Color = event.beachWalkStatus == .likely ? .black : .white

                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: event.type == .highTide ? "arrow.up" : "arrow.down")
                                .font(.system(size: fontSize * 0.65, weight: .bold))
                                .foregroundStyle(onBg ? textOnBg : tideColor)
                            Text(viewModel.formatTime(event.adjustedTime))
                                .font(.system(size: fontSize, weight: .medium).monospacedDigit())
                                .foregroundStyle(onBg ? textOnBg : .primary)
                        }
                        Text(event.heightFormatted)
                            .font(.system(size: fontSize * 0.9).monospacedDigit())
                            .foregroundStyle(onBg ? textOnBg : tideColor)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(bgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            // ── Sonne & Mond ──
            HStack(spacing: 16) {
                if let rise = astronomy.sunrise {
                    HStack(spacing: 4) {
                        Image(systemName: "sunrise.fill").foregroundStyle(.yellow)
                        Text(viewModel.formatTime(rise)).monospacedDigit()
                    }
                }
                if let set = astronomy.sunset {
                    HStack(spacing: 4) {
                        Image(systemName: "sunset.fill").foregroundStyle(.orange)
                        Text(viewModel.formatTime(set)).monospacedDigit()
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(astronomy.moonPhase.emoji)
                    Text(astronomy.moonPhase.rawValue).foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            // ── Wetter ──
            if let wx = viewModel.weather(for: day.date) {
                HStack(spacing: 14) {
                    // Temperatur
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium").foregroundStyle(.red)
                        Text("\(Int(wx.maxTemp.rounded()))°").foregroundStyle(.red)
                        Text("/").foregroundStyle(.secondary)
                        Text("\(Int(wx.minTemp.rounded()))°").foregroundStyle(.blue)
                    }
                    // Regen
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill").foregroundStyle(precipColor(wx.precipProb))
                        Text("\(wx.precipProb) %").foregroundStyle(precipColor(wx.precipProb))
                    }
                    // Sonnenstunden
                    HStack(spacing: 3) {
                        Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f h", wx.sunshineHours)).foregroundStyle(.primary)
                    }
                    // Bewölkung
                    HStack(spacing: 3) {
                        Image(systemName: cloudIcon(wx.cloudCover)).foregroundStyle(.gray)
                        Text("\(wx.cloudCover) %").foregroundStyle(.secondary)
                        Text(cloudLabel(wx.cloudCover)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)
            }

            Divider()
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}
