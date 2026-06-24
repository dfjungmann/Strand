import SwiftUI

struct BeachWalkView: View {
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
                            thresholdCard
                            ForEach(viewModel.tideDays) { day in
                                BeachDayCard(day: day, viewModel: viewModel)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Strandspaziergang")
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
    }

    // MARK: - Threshold Info Card

    private var thresholdCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Strandgang möglich wenn:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Niedrigwasser ≤ \(String(format: "%.2f m", viewModel.beachWalkThreshold))")
                    .font(.headline)
            }
            Spacer()
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
            systemImage: "figure.walk.circle",
            description: Text(viewModel.errorMessage ?? "Tippe auf Aktualisieren")
        )
    }
}

// MARK: - Beach Day Card

struct BeachDayCard: View {
    let day: TideDay
    let viewModel: TideViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.formatDayHeader(day.date))
                        .font(.headline)
                    if let lowest = day.lowestTide {
                        Text("Niedrigstes NW: \(lowest.heightFormatted)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                overallStatusIcon
            }
            .padding()

            Divider()

            // Events
            VStack(spacing: 0) {
                ForEach(day.events.filter { $0.type == .lowTide }) { event in
                    LowTideRow(event: event, viewModel: viewModel, threshold: viewModel.beachWalkThreshold)
                    if event.id != day.events.filter({ $0.type == .lowTide }).last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }

            if day.events.filter({ $0.type == .lowTide }).isEmpty {
                Text("Keine Niedrigwasser-Daten")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var overallStatusIcon: some View {
        Group {
            if day.hasBeachWalkOpportunity {
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Möglich")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red.opacity(0.7))
                    Text("Zu hoch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Low Tide Row

struct LowTideRow: View {
    let event: TideEvent
    let viewModel: TideViewModel
    let threshold: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.isBeachWalkPossible ? "figure.walk" : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(event.isBeachWalkPossible ? .green : .orange)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.formatTime(event.adjustedTime))
                    .font(.headline)
                    .monospacedDigit()
                Text("Niedrigwasser")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(event.heightFormatted)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(event.isBeachWalkPossible ? .green : .primary)

                heightGauge
            }
        }
        .padding()
    }

    private var heightGauge: some View {
        let maxHeight = 2.0
        let fraction = min(event.height / maxHeight, 1.0)
        let thresholdFraction = min(threshold / maxHeight, 1.0)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(event.isBeachWalkPossible ? Color.green : Color.orange)
                    .frame(width: geo.size.width * fraction, height: 6)

                // Threshold marker
                Rectangle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 2, height: 12)
                    .offset(x: geo.size.width * thresholdFraction - 1, y: -3)
            }
        }
        .frame(width: 80, height: 6)
    }
}
