import SwiftUI
import Charts

struct ChartView: View {
    let viewModel: TideViewModel
    @State private var selectedDay: TideDay?
    @State private var showAllDays = false

    var displayedDays: [TideDay] {
        if showAllDays { return viewModel.tideDays }
        return selectedDay.map { [$0] } ?? (viewModel.tideDays.first.map { [$0] } ?? [])
    }

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
                            daySelector
                            chartCard
                            legendCard
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Diagramm")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            if selectedDay == nil {
                selectedDay = viewModel.tideDays.first
            }
        }
        .onChange(of: viewModel.tideDays.count) {
            if selectedDay == nil || !viewModel.tideDays.contains(where: { $0.id == selectedDay?.id }) {
                selectedDay = viewModel.tideDays.first
            }
        }
    }

    // MARK: - Day Selector

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                dayChip(label: "Alle", isSelected: showAllDays) {
                    showAllDays = true
                    selectedDay = nil
                }
                ForEach(viewModel.tideDays) { day in
                    dayChip(
                        label: viewModel.formatShortDate(day.date),
                        isSelected: !showAllDays && selectedDay?.id == day.id,
                        beach: day.hasBeachWalkOpportunity
                    ) {
                        selectedDay = day
                        showAllDays = false
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func dayChip(label: String, isSelected: Bool, beach: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if beach {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gezeitenverlauf")
                .font(.headline)
                .padding(.horizontal, 4)

            if displayedDays.isEmpty {
                Text("Keine Daten")
                    .foregroundStyle(.secondary)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            } else {
                tideChart
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var tideChart: some View {
        Chart {
            // Threshold line for beach walk
            RuleMark(y: .value("Schwellenwert", viewModel.beachWalkThreshold))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.green.opacity(0.7))
                .annotation(position: .top, alignment: .leading) {
                    Text("Grenzwert \(String(format: "%.1f m", viewModel.beachWalkThreshold))")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.leading, 4)
                }

            ForEach(displayedDays) { day in
                let points = viewModel.chartPoints(for: day)

                // Area fill
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Zeit", point.time),
                        yStart: .value("Basis", 0.0),
                        yEnd: .value("Höhe", point.height)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Line
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
                ForEach(day.events) { event in
                    PointMark(
                        x: .value("Zeit", event.adjustedTime),
                        y: .value("Höhe", event.height)
                    )
                    .foregroundStyle(event.type == .highTide ? Color.blue : Color.orange)
                    .symbolSize(60)
                    .annotation(position: event.type == .highTide ? .top : .bottom) {
                        Text(event.heightFormatted)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(event.type == .highTide ? .blue : .orange)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 0.5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.1f m", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
                    .font(.caption2)
            }
        }
        .chartYScale(domain: 0...2.5)
        .frame(height: 220)
    }

    // MARK: - Legend Card

    private var legendCard: some View {
        VStack(spacing: 8) {
            if let day = showAllDays ? nil : (selectedDay ?? viewModel.tideDays.first) {
                ForEach(day.events) { event in
                    HStack {
                        Image(systemName: event.type.symbol)
                            .foregroundStyle(event.type == .highTide ? .blue : .orange)
                            .frame(width: 28)
                        Text(event.type.displayName)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.formatTime(event.adjustedTime))
                            .monospacedDigit()
                        Text(event.heightFormatted)
                            .monospacedDigit()
                            .fontWeight(.medium)
                            .foregroundStyle(event.type == .highTide ? .blue : .orange)
                            .frame(width: 60, alignment: .trailing)
                        if event.isBeachWalkPossible {
                            Image(systemName: "figure.walk")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    .font(.subheadline)
                    if event.id != day.events.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
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
