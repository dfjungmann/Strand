import SwiftUI
import Charts

// MARK: - Container with swipe navigation

struct DayDetailView: View {
    let initialDay: TideDay
    let viewModel: TideViewModel

    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(day: TideDay, viewModel: TideViewModel) {
        self.initialDay = day
        self.viewModel = viewModel
        let idx = viewModel.tideDays.firstIndex(where: { $0.id == day.id }) ?? 0
        self._currentIndex = State(initialValue: idx)
    }

    private var currentDay: TideDay {
        viewModel.tideDays[safe: currentIndex] ?? initialDay
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.tideDays.enumerated()), id: \.offset) { idx, day in
                    DayDetailContent(day: day, viewModel: viewModel)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(viewModel.formatDayHeader(currentDay.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation { currentIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentIndex == 0)

                        Button {
                            withAnimation { currentIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentIndex >= viewModel.tideDays.count - 1)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Content for one day

private struct DayDetailContent: View {
    let day: TideDay
    let viewModel: TideViewModel

    private var twoDays: [TideDay] {
        guard let idx = viewModel.tideDays.firstIndex(where: { $0.id == day.id }) else {
            return [day]
        }
        return Array(viewModel.tideDays[idx...].prefix(2))
    }

    private var hourlyTemps: [HourlyTemp] {
        viewModel.hourlyTemps(from: Calendar.current.startOfDay(for: day.date), dayCount: 2)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                tideChartCard
                if !hourlyTemps.isEmpty {
                    tempChartCard
                }
            }
            .padding()
        }
    }

    // MARK: - Tide Chart Card

    private var tideChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gezeiten – 2 Tage")
                .font(.headline)
                .padding(.horizontal, 4)
            tideChart
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var tideChart: some View {
        let points = viewModel.chartPoints(for: twoDays)
        let events = twoDays.flatMap { $0.events }
        let bounds = viewModel.dayBoundaries(for: twoDays)
        let maxH   = (events.map { $0.height }.max() ?? 2.0) + 0.4

        return Chart {
            ForEach(bounds, id: \.self) { b in
                RuleMark(x: .value("Tag", b))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color(.systemGray4))
            }
            RuleMark(y: .value("Sicher", viewModel.beachWalkThresholdSafe))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.green.opacity(0.8))
                .annotation(position: .top, alignment: .leading) {
                    Text("Sicher \(String(format: "%.1f m", viewModel.beachWalkThresholdSafe))")
                        .font(.caption2).foregroundStyle(.green).padding(.leading, 4)
                }
            RuleMark(y: .value("Wahrsch.", viewModel.beachWalkThresholdLikely))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.yellow.opacity(0.9))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Wahrsch. \(String(format: "%.1f m", viewModel.beachWalkThresholdLikely))")
                        .font(.caption2).foregroundStyle(.orange).padding(.trailing, 4)
                }
            // Beach walk windows (±1.5h around qualifying low tides)
            ForEach(events.filter { $0.type == .lowTide && $0.beachWalkStatus != .none }) { e in
                let start = e.adjustedTime.addingTimeInterval(-90 * 60)
                let end   = e.adjustedTime.addingTimeInterval( 90 * 60)
                let color: Color = e.beachWalkStatus == .safe ? .green : .yellow
                RectangleMark(
                    xStart: .value("Start", start),
                    xEnd:   .value("End",   end),
                    yStart: .value("0",     0.0),
                    yEnd:   .value("Top",   maxH)
                )
                .foregroundStyle(color.opacity(0.18))
            }

            ForEach(points) { p in
                AreaMark(x: .value("Zeit", p.time), yStart: .value("0", 0), yEnd: .value("H", p.height))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue.opacity(0.25), .blue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(points) { p in
                LineMark(x: .value("Zeit", p.time), y: .value("H", p.height))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(events) { e in
                PointMark(x: .value("Zeit", e.adjustedTime), y: .value("H", e.height))
                    .foregroundStyle(e.type == .highTide ? Color.blue : Color.orange)
                    .symbolSize(60)
                    .annotation(position: e.type == .highTide ? .top : .bottom, spacing: 2) {
                        VStack(spacing: 1) {
                            Text(viewModel.formatTime(e.adjustedTime))
                                .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                            Text(e.heightFormatted)
                                .font(.system(size: 9).monospacedDigit()).fontWeight(.semibold)
                                .foregroundStyle(e.type == .highTide ? .blue : .orange)
                        }
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 0.5)) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(String(format: "%.1f", d)).font(.caption2) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { v in
                AxisGridLine()
                AxisValueLabel(centered: false) {
                    if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                }
            }
        }
        .chartYScale(domain: 0...maxH)
        .frame(height: 260)
    }

    // MARK: - Temperature Chart Card

    private var tempChartCard: some View {
        let temps = hourlyTemps
        let minT  = (temps.min(by: { $0.temp < $1.temp })?.temp ?? 15) - 1
        let maxT  = (temps.max(by: { $0.temp < $1.temp })?.temp ?? 30) + 1
        let bounds = viewModel.dayBoundaries(for: twoDays)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Temperaturverlauf – 2 Tage").font(.headline)
                Spacer()
                Text("\(Int(minT + 1).description)° – \(Int(maxT - 1).description)°")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Chart {
                ForEach(bounds, id: \.self) { b in
                    RuleMark(x: .value("Tag", b))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color(.systemGray4))
                }
                ForEach(temps) { h in
                    AreaMark(x: .value("Zeit", h.time), yStart: .value("Min", minT), yEnd: .value("T", h.temp))
                        .foregroundStyle(.linearGradient(
                            colors: [.red.opacity(0.2), .orange.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(temps) { h in
                    LineMark(x: .value("Zeit", h.time), y: .value("T", h.temp))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text("\(Int(d))°").font(.caption2) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine()
                    AxisValueLabel(centered: false) {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: minT...maxT)
            .frame(height: 180)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - X-Axis Helpers

    private var xAxisValues: [Date] {
        guard let startDay = twoDays.first?.date else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let midnight = cal.startOfDay(for: startDay)
        return (0...4).map { cal.date(byAdding: .hour, value: $0 * 12, to: midnight)! }
    }

    private func xLabel(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let hour = cal.component(.hour, from: date)
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EE"
        dayFmt.locale = Locale(identifier: "de_DE")
        dayFmt.timeZone = TideService.canaryIslandsTimeZone
        return hour == 0 ? dayFmt.string(from: date) : "\(hour):00"
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
