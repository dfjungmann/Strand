import SwiftUI
import Charts

struct ChartView: View {
    let viewModel: TideViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.tideDays.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            daysPicker
                            chartCard
                            eventLegend
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Diagramm")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await viewModel.reload() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - Days Picker (zwei Zeilen)

    private var daysPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Zeile 1: Anzahl Tage
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TideViewModel.chartDayOptions, id: \.self) { n in
                        let isSelected = viewModel.chartDays == n
                        Button {
                            viewModel.chartDays = n
                        } label: {
                            Text(n == 1 ? "1 Tag" : "\(n) Tage")
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.blue : Color(.systemGray6))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Zeile 2: Starttag
            HStack(spacing: 8) {
                ForEach(TideViewModel.chartStartOptions, id: \.offset) { option in
                    let isSelected = viewModel.chartStartOffset == option.offset
                    Button {
                        viewModel.chartStartOffset = option.offset
                    } label: {
                        Text(option.label)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.orange : Color(.systemGray6))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let days = viewModel.chartDisplayDays
            HStack {
                Text(chartTitle(for: days))
                    .font(.headline)
                Spacer()
                Text("\(days.flatMap { $0.events }.count) Extrema")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            tideChart(days: days)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private func tideChart(days: [TideDay]) -> some View {
        let points = viewModel.chartPoints(for: days)
        let events = days.flatMap { $0.events }
        let boundaries = viewModel.dayBoundaries(for: days)
        let maxHeight = (events.map { $0.height }.max() ?? 2.0) + 0.3

        Chart {
            // Day boundary separators
            ForEach(boundaries, id: \.self) { boundary in
                RuleMark(x: .value("Tag", boundary))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color(.systemGray4))
                    .annotation(position: .top, alignment: .leading) {
                        Text(shortDayLabel(boundary))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
            }

            // Beach walk threshold
            RuleMark(y: .value("Grenzwert", viewModel.beachWalkThreshold))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.green.opacity(0.7))
                .annotation(position: .top, alignment: .trailing) {
                    Text("\(String(format: "%.1f m", viewModel.beachWalkThreshold))")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.trailing, 4)
                }

            // Area fill
            ForEach(points) { point in
                AreaMark(
                    x: .value("Zeit", point.time),
                    yStart: .value("Basis", 0.0),
                    yEnd: .value("Höhe", point.height)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue.opacity(0.25), .blue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // Tide curve
            ForEach(points) { point in
                LineMark(
                    x: .value("Zeit", point.time),
                    y: .value("Höhe", point.height)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.catmullRom)
            }

            // Event markers
            ForEach(events) { event in
                PointMark(
                    x: .value("Zeit", event.adjustedTime),
                    y: .value("Höhe", event.height)
                )
                .foregroundStyle(event.type == .highTide ? Color.blue : Color.orange)
                .symbolSize(55)
                .annotation(position: event.type == .highTide ? .top : .bottom, spacing: 2) {
                    Text(event.heightFormatted)
                        .font(.system(size: 9).monospacedDigit())
                        .fontWeight(.medium)
                        .foregroundStyle(event.type == .highTide ? .blue : .orange)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 0.5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.1f", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues(for: days)) { value in
                AxisGridLine()
                AxisValueLabel(centered: false) {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(date, dayCount: days.count))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...maxHeight)
        .frame(height: days.count <= 2 ? 220 : min(160 + CGFloat(days.count) * 20, 320))
    }

    // MARK: - Event Legend

    private var eventLegend: some View {
        let days = viewModel.chartDisplayDays
        let events = days.flatMap { $0.events }

        return VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { _, day in
                VStack(spacing: 0) {
                    HStack {
                        Text(viewModel.formatShortDate(day.date))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        Spacer()
                        if day.hasBeachWalkOpportunity {
                            Image(systemName: "figure.walk")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                    ForEach(day.events) { event in
                        HStack {
                            Image(systemName: event.type.symbol)
                                .foregroundStyle(event.type == .highTide ? .blue : .orange)
                                .frame(width: 24)
                            Text(event.type.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(viewModel.formatTime(event.adjustedTime))
                                .font(.subheadline)
                                .monospacedDigit()
                            Text(event.heightFormatted)
                                .font(.subheadline)
                                .monospacedDigit()
                                .fontWeight(.medium)
                                .foregroundStyle(event.type == .highTide ? .blue : .orange)
                                .frame(width: 62, alignment: .trailing)
                            if event.isBeachWalkPossible {
                                Image(systemName: "figure.walk")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Color.clear.frame(width: 14)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        if event.id != day.events.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }

                if day.id != days.last?.id {
                    Divider().padding(.top, 4)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Helpers

    private func chartTitle(for days: [TideDay]) -> String {
        guard let first = days.first, let last = days.last else { return "Gezeitenverlauf" }
        if days.count == 1 { return viewModel.formatDayHeader(first.date) }
        let f = DateFormatter()
        f.dateFormat = "d. MMM"
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TideService.canaryIslandsTimeZone
        return "\(f.string(from: first.date)) – \(f.string(from: last.date))"
    }

    private func shortDayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EE d.M."
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TideService.canaryIslandsTimeZone
        return f.string(from: date)
    }

    private func xAxisValues(for days: [TideDay]) -> [Date] {
        guard let first = days.first?.events.first?.adjustedTime,
              let last = days.last?.events.last?.adjustedTime else { return [] }
        let stride = days.count <= 2 ? 6 : (days.count <= 4 ? 12 : 24)
        var dates: [Date] = []
        var current = Calendar.current.date(bySetting: .minute, value: 0, of: first)!
        while current <= last {
            dates.append(current)
            current = Calendar.current.date(byAdding: .hour, value: stride, to: current)!
        }
        return dates
    }

    private func xAxisLabel(_ date: Date, dayCount: Int) -> String {
        let f = DateFormatter()
        f.timeZone = TideService.canaryIslandsTimeZone
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = dayCount <= 2 ? "HH:mm" : "EE HH:mm"
        return f.string(from: date)
    }

    // MARK: - States

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
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text(viewModel.errorMessage ?? "Tippe auf Aktualisieren")
        )
    }
}
