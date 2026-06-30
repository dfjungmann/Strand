import SwiftUI

/// Gezeiten-Uhr für Apple Watch (Layout angelehnt an iPhone / Bild 2).
struct WatchTideClockView: View {
    let viewModel: WatchTideViewModel

    // Farben wie TideClockView (iPhone)
    private let skyBackground = Color(red: 0.82, green: 0.91, blue: 0.97)
    private let heightBlue = Color(red: 0.08, green: 0.32, blue: 0.72)
    private let markerBlue = Color(red: 0.35, green: 0.55, blue: 0.82)
    private let countdownGray = Color(white: 0.38)
    private let outerLabelTime = Color(white: 0.08)
    private let outerLabelHeight = Color(white: 0.18)

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var clock: TideClockState {
        TideClockState(now: now, events: viewModel.allEvents)
    }

    private var tz: TimeZone { TideService.canaryIslandsTimeZone }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.tideDays.isEmpty {
                ProgressView("Lade…")
                    .tint(outerLabelTime)
                    .foregroundStyle(outerLabelTime)
            } else if let error = viewModel.errorMessage, viewModel.tideDays.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(outerLabelTime)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(outerLabelTime)
                        .multilineTextAlignment(.center)
                }
            } else {
                clockContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(skyBackground)
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .onReceive(timer) { now = $0 }
    }

    private var clockContent: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let tideFontSize = w * 0.088
            let cx = w / 2
            let cy = h / 2
            // Volle Fläche nutzen — Kreis nach kleinerer Kante, nicht nach Text-Resthöhe
            let r = min(w, h) * 0.49

            ZStack {
                clockFace(cx: cx, cy: cy, r: r)
                needle(cx: cx, cy: cy, r: r)
                heightLabel(cx: cx, cy: cy, r: r)
                centerReadout(cx: cx, cy: cy, r: r)

                VStack(spacing: 2) {
                    tideHighRow(fontSize: tideFontSize, width: w)
                    Spacer(minLength: 0)
                    tideLowRow(fontSize: tideFontSize, width: w)
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Tide info

    @ViewBuilder
    private func tideHighRow(fontSize: CGFloat, width: CGFloat) -> some View {
        if let displayed = clock.displayedHighTide {
            tideEventLine(displayed, fontSize: fontSize, width: width)
        }
    }

    @ViewBuilder
    private func tideLowRow(fontSize: CGFloat, width: CGFloat) -> some View {
        if let displayed = clock.displayedLowTide {
            tideEventLine(displayed, fontSize: fontSize, width: width)
        }
    }

    private func tideEventLine(
        _ displayed: TideClockState.DisplayedTide,
        fontSize: CGFloat,
        width: CGFloat
    ) -> some View {
        let event = displayed.event
        return HStack(spacing: 1) {
            watchTideMarker(for: displayed)
            Text(formatTime(event.adjustedTime, "HH:mm"))
                .foregroundStyle(outerLabelTime)
            Text("|")
                .foregroundStyle(outerLabelTime)
            Text(tideHeightLabel(event.height))
                .foregroundStyle(outerLabelHeight)
        }
        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .frame(maxWidth: width - 2)
    }

    @ViewBuilder
    private func watchTideMarker(for displayed: TideClockState.DisplayedTide) -> some View {
        let letter = displayed.recency == .past ? "a" : "n"
        let color: Color = displayed.recency == .past
            ? Color(red: 0.88, green: 0.12, blue: 0.10)
            : Color(red: 0.15, green: 0.55, blue: 0.22)
        Text(letter)
            .foregroundStyle(color)
    }

    // MARK: - Face

    @ViewBuilder
    private func clockFace(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Canvas { ctx, _ in
            fillRing(ctx, cx, cy, r * 0.87, r, Color(white: 0.74))
            fillRing(ctx, cx, cy, r * 0.845, r * 0.87, Color(red: 0.88, green: 0.72, blue: 0.22))
            fillRing(ctx, cx, cy, r * 0.78, r * 0.845, Color(white: 0.68))

            let innerR = r * 0.78
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - innerR, y: cy - innerR,
                                       width: innerR * 2, height: innerR * 2)),
                with: .color(Color(red: 0.97, green: 0.98, blue: 1.0))
            )

            if let arc = clock.strandyArcWindow {
                let window = arc
                TideBeachWalk.drawStrandyArcStroke(
                    &ctx,
                    cx: cx,
                    cy: cy,
                    arcRadius: r * 0.66,
                    startClockAngleDeg: window.startClockAngleDeg,
                    endClockAngleDeg: window.endClockAngleDeg,
                    lineWidth: r * 0.18,
                    heightAtFraction: { fraction in
                        let span = window.endTime.timeIntervalSince(window.startTime)
                        let t = window.startTime.addingTimeInterval(span * fraction)
                        return clock.height(at: t) ?? 0
                    }
                )
            }

            let tickOuter = r * 0.76
            for i in stride(from: 0, to: 60, by: 5) {
                let deg = Double(i) / 60.0 * 360.0 - 90.0
                let rad = deg * .pi / 180.0
                let tickLen = r * 0.055
                var lp = Path()
                lp.move(to: CGPoint(x: cx + (tickOuter - tickLen) * cos(rad),
                                    y: cy + (tickOuter - tickLen) * sin(rad)))
                lp.addLine(to: CGPoint(x: cx + tickOuter * cos(rad),
                                       y: cy + tickOuter * sin(rad)))
                ctx.stroke(lp, with: .color(Color(white: 0.12).opacity(0.85)), lineWidth: 1.5)
            }

            let markerR = r * 0.80
            let tri = r * 0.065
            drawTriangle(ctx, cx: cx, cy: cy - markerR, size: tri,
                         color: markerBlue, pointingUp: true)
            drawTriangle(ctx, cx: cx, cy: cy + markerR, size: tri,
                         color: markerBlue, pointingUp: false)
        }
        .allowsHitTesting(false)
    }

    private func fillRing(_ ctx: GraphicsContext,
                          _ cx: CGFloat, _ cy: CGFloat,
                          _ innerR: CGFloat, _ outerR: CGFloat,
                          _ color: Color) {
        var p = Path()
        p.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2))
        p.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
        ctx.fill(p, with: .color(color), style: FillStyle(eoFill: true))
    }

    private func drawTriangle(_ ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                              size: CGFloat, color: Color, pointingUp: Bool) {
        var p = Path()
        if pointingUp {
            p.move(to: CGPoint(x: cx, y: cy - size / 2))
            p.addLine(to: CGPoint(x: cx - size / 2, y: cy + size / 2))
            p.addLine(to: CGPoint(x: cx + size / 2, y: cy + size / 2))
        } else {
            p.move(to: CGPoint(x: cx, y: cy + size / 2))
            p.addLine(to: CGPoint(x: cx - size / 2, y: cy - size / 2))
            p.addLine(to: CGPoint(x: cx + size / 2, y: cy - size / 2))
        }
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    // MARK: - Needle

    @ViewBuilder
    private func needle(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Canvas { ctx, _ in
            let rad = (clock.needleAngleDeg - 90.0) * .pi / 180.0
            let perp = rad + .pi / 2
            let tabCx = r * 0.66
            let hLen = r * 0.07
            let hWid = r * 0.032
            let tabCenter = CGPoint(x: cx + tabCx * cos(rad), y: cy + tabCx * sin(rad))

            let lineEnd = tabCx - hLen
            let tip = CGPoint(x: cx + lineEnd * cos(rad), y: cy + lineEnd * sin(rad))
            var line = Path()
            line.move(to: CGPoint(x: cx, y: cy))
            line.addLine(to: tip)
            ctx.stroke(line, with: .color(.red.opacity(0.85)),
                       style: StrokeStyle(lineWidth: max(5.0, r * 0.022), lineCap: .butt))

            let corners: [CGPoint] = [
                CGPoint(x: tabCenter.x + hLen * cos(rad) + hWid * cos(perp),
                        y: tabCenter.y + hLen * sin(rad) + hWid * sin(perp)),
                CGPoint(x: tabCenter.x + hLen * cos(rad) - hWid * cos(perp),
                        y: tabCenter.y + hLen * sin(rad) - hWid * sin(perp)),
                CGPoint(x: tabCenter.x - hLen * cos(rad) - hWid * cos(perp),
                        y: tabCenter.y - hLen * sin(rad) - hWid * sin(perp)),
                CGPoint(x: tabCenter.x - hLen * cos(rad) + hWid * cos(perp),
                        y: tabCenter.y - hLen * sin(rad) + hWid * sin(perp)),
            ]
            var tab = Path()
            tab.move(to: corners[0])
            corners.dropFirst().forEach { tab.addLine(to: $0) }
            tab.closeSubpath()
            ctx.fill(tab, with: .color(.red))

            let dotR = max(4.0, r * 0.014)
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
                with: .color(.red)
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Labels

    @ViewBuilder
    private func heightLabel(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let fSize = r * 0.30
        let rad = (clock.needleAngleDeg - 90.0) * .pi / 180.0
        let tabR = r * 0.84
        let x = cx + tabR * cos(rad)
        let y = cy + tabR * sin(rad)

        Text(TideDisplaySettings.displayHeightValueFormatted(clock.currentHeight))
            .font(.system(size: fSize, weight: .black, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(heightBlue)
            .shadow(color: .white, radius: 2)
            .shadow(color: .white.opacity(0.8), radius: 5)
            .rotationEffect(.degrees(clock.tideHeightLabelRotation))
            .position(x: x, y: y)
            .animation(.linear(duration: 1), value: clock.needleAngleDeg)
    }

    @ViewBuilder
    private func centerReadout(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let innerR = r * 0.78
        let miniClockSize = innerR * 0.68
        let countdownSize = innerR * 0.26

        MiniAnalogClockView(date: now, size: miniClockSize)
            .position(x: cx, y: cy - r * 0.05 - miniClockSize * 0.60)

        VStack(spacing: r * 0.008) {
            Text("noch")
                .font(.system(size: countdownSize * 0.55, weight: .semibold))
                .foregroundStyle(countdownGray)

            Text(countdownToNextExtreme)
                .font(.system(size: countdownSize, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.black)
        }
        .position(x: cx, y: cy + r * 0.14)
    }

    // MARK: - Formatting

    private var countdownToNextExtreme: String {
        guard let next = clock.nextEvent else { return "--:--" }
        let secs = max(0, Int(next.adjustedTime.timeIntervalSince(now)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    private func tideHeightLabel(_ rawHeight: Double) -> String {
        "\(TideDisplaySettings.displayHeightValueFormatted(rawHeight))m"
    }

    private func formatTime(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.dateFormat = pattern
        f.timeZone = tz
        return f.string(from: date)
    }
}

#Preview {
    WatchTideClockView(viewModel: WatchTideViewModel())
}

/// Kleine Analoguhr im Inneren der Gezeiten-Uhr (12/3/6/9, Stunden- + Minutenzeiger).
private struct MiniAnalogClockView: View {
    let date: Date
    let size: CGFloat

    private var hourAngle: Double {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date) % 12)
        let m = Double(cal.component(.minute, from: date))
        return (h + m / 60.0) / 12.0 * 360.0
    }

    private var minuteAngle: Double {
        let m = Double(Calendar.current.component(.minute, from: date))
        return m / 60.0 * 360.0
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let r = min(canvasSize.width, canvasSize.height) / 2 * 0.94

            // Markierungen nur bei 12, 3, 6, 9
            for hour in [0, 3, 6, 9] {
                let deg = Double(hour) / 12.0 * 360.0 - 90.0
                let rad = deg * .pi / 180.0
                let tickLen = r * 0.18
                let outer = r * 0.88
                var tick = Path()
                tick.move(to: CGPoint(x: cx + (outer - tickLen) * cos(rad),
                                      y: cy + (outer - tickLen) * sin(rad)))
                tick.addLine(to: CGPoint(x: cx + outer * cos(rad),
                                         y: cy + outer * sin(rad)))
                ctx.stroke(tick, with: .color(Color(white: 0.25)),
                           style: StrokeStyle(lineWidth: max(1.5, r * 0.06), lineCap: .round))
            }

            drawHand(ctx, cx: cx, cy: cy, length: r * 0.52, width: max(2.0, r * 0.07),
                     angleDeg: hourAngle, color: Color(white: 0.12))
            drawHand(ctx, cx: cx, cy: cy, length: r * 0.72, width: max(1.5, r * 0.045),
                     angleDeg: minuteAngle, color: Color(white: 0.12))

            let hubR = max(2.0, r * 0.05)
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - hubR, y: cy - hubR, width: hubR * 2, height: hubR * 2)),
                with: .color(Color(white: 0.12))
            )
        }
        .frame(width: size, height: size)
    }

    private func drawHand(_ ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          length: CGFloat, width: CGFloat, angleDeg: Double, color: Color) {
        let rad = (angleDeg - 90.0) * .pi / 180.0
        let tip = CGPoint(x: cx + length * cos(rad), y: cy + length * sin(rad))
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy))
        path.addLine(to: tip)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
