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
                ToolbarItem(placement: .navigationBarLeading) {
                    daysPicker
                }
            }
        }
    }

    // MARK: - Subviews

    private var tideList: some View {
        List {
            ForEach(viewModel.tideDays) { day in
                Section {
                    ForEach(day.events) { event in
                        TideEventRow(event: event, viewModel: viewModel)
                    }
                } header: {
                    DaySectionHeader(day: day, viewModel: viewModel)
                }
            }

            Section {
                footerInfo
            }
        }
        .listStyle(.insetGrouped)
    }

    private var footerInfo: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Zeiten: Puerto de la Luz \(offsetDescription). Kanarische Zeit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var offsetDescription: String {
        let offset = viewModel.timeOffsetMinutes
        if offset == 0 { return "" }
        return offset < 0 ? "−\(abs(offset)) Min." : "+\(offset) Min."
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Lade Gezeitendaten…")
                .foregroundStyle(.secondary)
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
        Button {
            Task { await viewModel.reload() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
    }

    private var daysPicker: some View {
        Menu {
            ForEach(TideViewModel.availableDays, id: \.self) { days in
                Button("\(days) Tage") {
                    viewModel.selectedDays = days
                    Task { await viewModel.reload() }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(viewModel.selectedDays) Tage")
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .font(.subheadline)
        }
    }
}

// MARK: - Tide Event Row

struct TideEventRow: View {
    let event: TideEvent
    let viewModel: TideViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: event.type.symbol)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            // Time
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.formatTime(event.adjustedTime))
                    .font(.headline)
                    .monospacedDigit()
                Text(event.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Height
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.heightFormatted)
                    .font(.headline)
                    .monospacedDigit()
                if event.isBeachWalkPossible {
                    beachBadge
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch event.type {
        case .highTide: return .blue
        case .lowTide: return .orange
        }
    }

    private var beachBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "figure.walk")
            Text("Strandgang")
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.green.opacity(0.15))
        .foregroundStyle(.green)
        .clipShape(Capsule())
    }
}

// MARK: - Day Section Header

struct DaySectionHeader: View {
    let day: TideDay
    let viewModel: TideViewModel

    var body: some View {
        HStack {
            Text(viewModel.formatDayHeader(day.date))
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            if day.hasBeachWalkOpportunity {
                Image(systemName: "sun.and.horizon.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }
}
