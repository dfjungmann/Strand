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
        VStack(spacing: 10) {
            thresholdRow(
                color: .green,
                icon: "checkmark.circle.fill",
                label: "Sicher",
                value: viewModel.beachWalkThresholdSafe
            )
            Divider()
            thresholdRow(
                color: .yellow,
                icon: "exclamationmark.circle.fill",
                label: "Wahrscheinlich",
                value: viewModel.beachWalkThresholdLikely
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func thresholdRow(color: Color, icon: String, label: String, value: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.headline)
                Text("Niedrigwasser ≤ \(String(format: "%.2f m", value))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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
                    LowTideRow(event: event, viewModel: viewModel)
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
        let bestStatus = day.events.filter { $0.type == .lowTide }
            .map { $0.beachWalkStatus }
            .max { a, b in
                let order: [BeachWalkStatus] = [.none, .likely, .safe]
                return (order.firstIndex(of: a) ?? 0) < (order.firstIndex(of: b) ?? 0)
            } ?? .none

        return Group {
            switch bestStatus {
            case .safe:
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                    Text("Sicher").font(.caption2).foregroundStyle(.green)
                }
            case .likely:
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(.yellow)
                    Text("Wahrsch.").font(.caption2).foregroundStyle(.secondary)
                }
            case .none:
                VStack(spacing: 2) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.red.opacity(0.7))
                    Text("Zu hoch").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Low Tide Row

struct LowTideRow: View {
    let event: TideEvent
    let viewModel: TideViewModel

    private var statusColor: Color {
        switch event.beachWalkStatus {
        case .safe:   return .green
        case .likely: return .yellow
        case .none:   return .orange
        }
    }

    private var statusIcon: String {
        switch event.beachWalkStatus {
        case .safe:   return "figure.walk"
        case .likely: return "figure.walk"
        case .none:   return "arrow.down.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
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
                    .foregroundStyle(statusColor)
                heightGauge
            }
        }
        .padding()
    }

    private var heightGauge: some View {
        let maxH = 2.0
        let fraction       = min(event.height / maxH, 1.0)
        let safeFraction   = min(viewModel.beachWalkThresholdSafe   / maxH, 1.0)
        let likelyFraction = min(viewModel.beachWalkThresholdLikely / maxH, 1.0)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(statusColor)
                    .frame(width: geo.size.width * fraction, height: 6)
                // Likely marker (yellow)
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 2, height: 12)
                    .offset(x: geo.size.width * likelyFraction - 1, y: -3)
                // Safe marker (green)
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2, height: 12)
                    .offset(x: geo.size.width * safeFraction - 1, y: -3)
            }
        }
        .frame(width: 80, height: 6)
    }
}
