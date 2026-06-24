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

            // ── Spalten: Zeit + Höhe übereinander, bei Strandgang farbig ──
            HStack(spacing: 4) {
                ForEach(day.events) { event in
                    let isBeach = event.isBeachWalkPossible
                    let tideColor: Color = event.type == .highTide ? .blue : .orange

                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: event.type == .highTide ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(isBeach ? .white : tideColor)
                            Text(viewModel.formatTime(event.adjustedTime))
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(isBeach ? .white : .primary)
                        }
                        Text(event.heightFormatted)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(isBeach ? .white : tideColor)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(isBeach ? Color.green : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            Divider()
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}
