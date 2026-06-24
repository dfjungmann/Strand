import SwiftUI
import Charts

struct DayDetailView: View {
    let day: TideDay
    let viewModel: TideViewModel

    @Environment(\.dismiss) private var dismiss

    /// The two-day window: selected day + next day
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    tideChartCard
                    if !hourlyTemps.isEmpty {
                        tempChartCard
                    }
                }
                .padding()
            }
            .navigationTitle(viewModel.formatDayHeader(day.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
        let points  = viewModel.chartPoints(for: twoDays)
        let events  = twoDays.flatMap { $0.events }
        let bounds  = viewModel.dayBoundaries(for: twoDays)
        let maxH    = (events.map { $0.height }.max() ?? 2.0) + 0.4

        return Chart {
            // Day boundary
            ForEach(bounds, id: \.self) { b in
                RuleMark(x: .value("Tag", b))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color(.systemGray4))
            }

            // Safe threshold (green)
            RuleMark(y: .value("Sicher", viewModel.beachWalkThresholdSafe))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.green.opacity(0.8))
                .annotation(position: .top, alignment: .leading) {
                    Text("Sicher \(String(format: "%.1f m", viewModel.beachWalkThresholdSafe))")
                        .font(.caption2).foregroundStyle(.green).padding(.leading, 4)
                }

            // Likely threshold (yellow)
            RuleMark(y: .value("Wahrsch.", viewModel.beachWalkThresholdLikely))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.yellow.opacity(0.9))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Wahrsch. \(String(format: "%.1f m", viewModel.beachWalkThresholdLikely))")
                        .font(.caption2).foregroundStyle(.orange).padding(.trailing, 4)
                }

            // Area fill
            ForEach(points) { p in
                AreaMark(x: .value("Zeit", p.time), yStart: .value("0", 0), yEnd: .value("H", p.height))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue.opacity(0.25), .blue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }

            // Tide line
            ForEach(points) { p in
                LineMark(x: .value("Zeit", p.time), y: .value("H", p.height))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }

            // Event markers + labels
            ForEach(events) { e in
                PointMark(x: .value("Zeit", e.adjustedTime), y: .value("H", e.height))
                    .foregroundStyle(e.type == .highTide ? Color.blue : Color.orange)
                    .symbolSize(60)
                    .annotation(position: e.type == .highTide ? .top : .bottom, spacing: 2) {
                        VStack(spacing: 1) {
                            Text(viewModel.formatTime(e.adjustedTime))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(e.heightFormatted)
                                .font(.system(size: 9).monospacedDigit())
                                .fontWeight(.semibold)
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
                    if let d = v.as(Date.self) {
                        Text(xLabel(d)).font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...maxH)
        .frame(height: 260)
    }

    // MARK: - Temperature Chart Card

    private var tempChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Temperaturverlauf – 2 Tage")
                    .font(.headline)
                Spacer()
                if let min = hourlyTemps.min(by: { $0.temp < $1.temp }),
                   let max = hourlyTemps.max(by: { $0.temp < $1.temp }) {
                    Text("\(Int(min.temp.rounded()))° – \(Int(max.temp.rounded()))°")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            tempChart
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var tempChart: some View {
        let bounds = viewModel.dayBoundaries(for: twoDays)
        let temps  = hourlyTemps
        let minT   = (temps.min(by: { $0.temp < $1.temp })?.temp ?? 15) - 1
        let maxT   = (temps.max(by: { $0.temp < $1.temp })?.temp ?? 30) + 1

        return Chart {
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

    // MARK: - X-Axis Helpers

    /// Marks every 12 hours, snapped to midnight/noon
    private var xAxisValues: [Date] {
        guard let startDay = twoDays.first?.date else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TideService.canaryIslandsTimeZone
        let midnight = cal.startOfDay(for: startDay)
        // 0h, 12h, 24h, 36h, 48h  → 5 clean marks
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
        let dayStr = dayFmt.string(from: date)

        // midnight → "Di." / "Mi." ; noon → "12:00"
        return hour == 0 ? dayStr : "\(hour):00"
    }
}
