import SwiftUI

// MARK: - Tide Clock View

struct TideClockView: View {
    let viewModel: TideViewModel
    @Binding var selectedTab: Int

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Tide data helpers

    private var allEvents: [TideEvent] {
        viewModel.tideDays
            .flatMap { $0.events }
            .sorted { $0.adjustedTime < $1.adjustedTime }
    }

    /// Most recent tide event at or before now
    private var prevEvent: TideEvent? {
        allEvents.last { $0.adjustedTime <= now }
    }

    /// Next tide event after now
    private var nextEvent: TideEvent? {
        allEvents.first { $0.adjustedTime > now }
    }

    /// 0…1 fraction through the current half-cycle
    private var cycleProgress: Double {
        guard let p = prevEvent, let n = nextEvent else { return 0 }
        let elapsed = now.timeIntervalSince(p.adjustedTime)
        let total   = n.adjustedTime.timeIntervalSince(p.adjustedTime)
        return max(0, min(1, elapsed / total))
    }

    /// Needle angle in degrees: 0° = top (high tide), clockwise → 180° = bottom (low tide)
    private var needleAngleDeg: Double {
        guard let p = prevEvent else { return 0 }
        return p.type == .highTide
            ? cycleProgress * 180.0           // Falling: 0° → 180°
            : 180.0 + cycleProgress * 180.0   // Rising:  180° → 360°
    }

    /// Cosine-interpolated current tide height (law of cosines for tidal motion)
    private var currentHeight: Double {
        guard let p = prevEvent, let n = nextEvent else { return 0 }
        let h0 = p.height, h1 = n.height
        return (h0 + h1) / 2.0 + (h0 - h1) / 2.0 * cos(.pi * cycleProgress)
    }

    private var isRising: Bool { prevEvent?.type == .lowTide }

    /// High tide event anchoring the current half-cycle
    private var cycleHighTide: TideEvent? {
        prevEvent?.type == .highTide ? prevEvent : nextEvent
    }

    /// Low tide event anchoring the current half-cycle
    private var cycleLowTide: TideEvent? {
        prevEvent?.type == .lowTide ? prevEvent : nextEvent
    }

    /// Nearest water temperature from marine data to a given tide event time
    private func waterTemp(near event: TideEvent) -> Double? {
        viewModel.hourlyMarine
            .min(by: { abs($0.time.timeIntervalSince(event.adjustedTime))
                     < abs($1.time.timeIntervalSince(event.adjustedTime)) })?
            .waterTemp
    }

    /// Countdown string to the next tide extreme
    private var countdownString: String {
        guard let next = nextEvent else { return "" }
        let secs = max(0, next.adjustedTime.timeIntervalSince(now))
        let h = Int(secs) / 3600
        let m = Int(secs) % 3600 / 60
        let s = Int(secs) % 60
        return h > 0
            ? String(format: "%dh %02dm", h, m)
            : String(format: "%dm %02ds", m, s)
    }

    /// Whether the next event is a high tide (used to format countdown label)
    private var nextIsHigh: Bool { nextEvent?.type == .highTide }

    /// Arc half-span (degrees) for ±90 min beach-walk window on clock face
    private var beachWalkArcSpan: Double {
        guard let p = prevEvent, let n = nextEvent else { return 24.0 }
        let halfCycleSec = n.adjustedTime.timeIntervalSince(p.adjustedTime)
        return 90.0 * 60.0 / halfCycleSec * 180.0
    }

    // MARK: - Time formatting

    private var tz: TimeZone { TideService.canaryIslandsTimeZone }

    private func hm(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = tz
        return f.string(from: date)
    }
    private func ss(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "ss"; f.timeZone = tz
        return f.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 0.82, green: 0.91, blue: 0.97).ignoresSafeArea()

            if viewModel.tideDays.isEmpty {
                ProgressView("Lade…").tint(.white).foregroundStyle(.white)
            } else {
                GeometryReader { geo in
                    let w  = geo.size.width
                    let h  = geo.size.height
                    let r  = min(w, h) * 0.44
                    let cx = w / 2
                    let cy = h / 2

                    ZStack {
                        clockFaceCanvas(cx: cx, cy: cy, r: r)
                        needleCanvas(cx: cx, cy: cy, r: r)
                        tideMarkerViews(cx: cx, cy: cy, r: r)
                        centerReadout(cx: cx, cy: cy, r: r)
                        outerTideLabels(cx: cx, cy: cy, r: r)
                    }
                }
            }
        }
        .onReceive(timer) { now = $0 }
        .gesture(
            DragGesture(minimumDistance: 60)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    if v.translation.width >  60 { withAnimation { selectedTab = 0 } }
                    if v.translation.width < -60 { withAnimation { selectedTab = 2 } }
                }
        )
    }

    // MARK: - Clock face (Canvas)

    @ViewBuilder
    private func clockFaceCanvas(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Canvas { ctx, _ in
            // Rings (outside → inside)
            fillRing(ctx, cx, cy, r * 0.87, r,        Color(white: 0.74))
            fillRing(ctx, cx, cy, r * 0.81, r * 0.87, Color(red: 0.88, green: 0.72, blue: 0.22))
            fillRing(ctx, cx, cy, r * 0.76, r * 0.81, Color(white: 0.68))
            fillRing(ctx, cx, cy, r * 0.65, r * 0.76, Color(red: 0.93, green: 0.96, blue: 0.99))

            // Strandy-Bogen (Farbverlauf wie Tab Tabelle) um Niedrigwasser-Position (180°)
            if let lt = cycleLowTide, lt.beachWalkStatus != .none {
                let arcColor = viewModel.beachWalkGradientColors(rawHeight: lt.height).background
                    .opacity(0.75)
                let span = beachWalkArcSpan
                let startDeg = 180.0 - span - 90.0   // convert to standard angle (0=right)
                let endDeg   = 180.0 + span - 90.0
                let arcR     = r * 0.66
                var arc = Path()
                arc.addArc(center: CGPoint(x: cx, y: cy),
                           radius: arcR,
                           startAngle: .degrees(startDeg),
                           endAngle:   .degrees(endDeg),
                           clockwise: false)
                ctx.stroke(arc, with: .color(arcColor),
                           style: StrokeStyle(lineWidth: r * 0.18, lineCap: .butt))
            }

            // Tick marks
            let tickOuter = r * 0.74
            for i in 0..<60 {
                let deg     = Double(i) / 60.0 * 360.0 - 90.0
                let rad     = deg * .pi / 180.0
                let isMajor = i % 5 == 0
                let tickLen: CGFloat = isMajor ? r * 0.070 : r * 0.038
                let lw:      CGFloat = isMajor ? 2.2 : 1.0
                let p0 = CGPoint(x: cx + (tickOuter - tickLen) * cos(rad),
                                 y: cy + (tickOuter - tickLen) * sin(rad))
                let p1 = CGPoint(x: cx + tickOuter * cos(rad),
                                 y: cy + tickOuter * sin(rad))
                var lp = Path(); lp.move(to: p0); lp.addLine(to: p1)
                ctx.stroke(lp, with: .color(Color(white: 0.12).opacity(isMajor ? 0.85 : 0.35)),
                           lineWidth: lw)
            }

            // Innerer Bereich — helles Zifferblatt (kein Blau)
            let innerR = r * 0.64
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - innerR, y: cy - innerR,
                                       width: innerR * 2, height: innerR * 2)),
                with: .color(Color(red: 0.97, green: 0.98, blue: 1.0))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func fillRing(_ ctx: GraphicsContext,
                          _ cx: CGFloat, _ cy: CGFloat,
                          _ innerR: CGFloat, _ outerR: CGFloat,
                          _ color: Color) {
        var p = Path()
        p.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerR,
                                width: outerR * 2, height: outerR * 2))
        p.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR,
                                width: innerR * 2, height: innerR * 2))
        ctx.fill(p, with: .color(color), style: FillStyle(eoFill: true))
    }

    // MARK: - Needle

    @ViewBuilder
    private func needleCanvas(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Canvas { ctx, _ in
            let rad = (needleAngleDeg - 90.0) * .pi / 180.0
            let perp = rad + .pi / 2

            // Thin line from centre to ~80% of inner sphere
            let lineLen = r * 0.46
            let tipLine = CGPoint(x: cx + lineLen * cos(rad), y: cy + lineLen * sin(rad))
            var line = Path(); line.move(to: CGPoint(x: cx, y: cy)); line.addLine(to: tipLine)
            ctx.stroke(line, with: .color(.red.opacity(0.80)), lineWidth: 2.0)

            // Rectangular tab at bezel position
            let tabCx = r * 0.66
            let tabCenter = CGPoint(x: cx + tabCx * cos(rad), y: cy + tabCx * sin(rad))
            let hLen: CGFloat = r * 0.065
            let hWid: CGFloat = r * 0.028
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
            var tab = Path(); tab.move(to: corners[0])
            corners.dropFirst().forEach { tab.addLine(to: $0) }
            tab.closeSubpath()
            ctx.fill(tab, with: .color(.red))

            // Centre dot
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)),
                with: .color(.red)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Tide markers (triangles at top / bottom of bezel)

    @ViewBuilder
    private func tideMarkerViews(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let markerR  = r * 0.795
        let triSize  = r * 0.13
        let blue     = Color(red: 0.35, green: 0.55, blue: 0.82)

        ZStack {
            // ▲ High tide at top (12 o'clock)
            TideTriangle()
                .fill(blue)
                .frame(width: triSize, height: triSize)
                .position(x: cx, y: cy - markerR)

            // ▽ Low tide at bottom (6 o'clock)
            TideTriangle()
                .fill(blue)
                .rotationEffect(.degrees(180))
                .frame(width: triSize, height: triSize)
                .position(x: cx, y: cy + markerR)

            // Inner ring label texts
            Text("H i g h   T i d e")
                .font(.system(size: r * 0.058, weight: .thin, design: .monospaced))
                .foregroundStyle(Color(white: 0.15).opacity(0.65))
                .position(x: cx, y: cy - r * 0.635)

            Text("L o w   T i d e")
                .font(.system(size: r * 0.058, weight: .thin, design: .monospaced))
                .foregroundStyle(Color(white: 0.15).opacity(0.65))
                .position(x: cx, y: cy + r * 0.635)
        }
    }

    // MARK: - Centre readout

    @ViewBuilder
    private func centerReadout(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let innerR = r * 0.64
        let fSize  = innerR * 0.36
        let padH   = r * 0.045
        let padV   = r * 0.028
        let corner = r * 0.045
        let maxW   = innerR * 1.75
        let heightBlue = Color(red: 0.08, green: 0.32, blue: 0.72)
        let countdownBg = Color(white: 0.38)

        VStack(spacing: r * 0.032) {
            // HH:MM :ss — Flip-Uhr-Stil (monospaced black), schwarz, ohne Hintergrund
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(hm(now))
                    .font(.system(size: fSize * 1.08, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                Text(":\(ss(now))")
                    .font(.system(size: fSize * 0.58, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(0.50))
            }

            // ▲/▼ Gezeitenhöhe — blau, ohne Hintergrund
            HStack(spacing: 4) {
                Image(systemName: isRising ? "arrow.up" : "arrow.down")
                    .font(.system(size: fSize * 0.42, weight: .bold))
                    .foregroundStyle(heightBlue)
                Text(viewModel.displayHeightFormatted(currentHeight))
                    .font(.system(size: fSize * 0.88, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(heightBlue)
            }

            // Countdown zum nächsten Extrem — mittleres Grau
            Text("\(nextIsHigh ? "↑" : "↓")  \(countdownString)")
                .font(.system(size: fSize * 0.46, weight: .medium, design: .monospaced)
                    .monospacedDigit())
                .foregroundStyle(.white.opacity(0.90))
                .padding(.horizontal, padH * 0.9)
                .padding(.vertical, padV * 0.9)
                .background(countdownBg.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: corner * 0.9))
        }
        .frame(maxWidth: maxW)
        .position(x: cx, y: cy)
    }

    // MARK: - Outer tide time labels (above / below ring)

    @ViewBuilder
    private func outerTideLabels(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let labelR = r * 1.22
        let topOffset = r * 0.10
        let fSize  = r * 0.115

        ZStack {
            if let ht = cycleHighTide {
                let isNext = (ht.id == nextEvent?.id)
                VStack(spacing: 2) {
                    Text(hm(ht.adjustedTime))
                        .font(.system(size: fSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.08))
                    Text(viewModel.displayHeightFormatted(ht.height))
                        .font(.system(size: fSize, weight: .regular))
                        .foregroundStyle(Color(white: 0.18))
                    if let wt = waterTemp(near: ht) {
                        HStack(spacing: 3) {
                            Image(systemName: "thermometer.medium")
                            Text(String(format: "%.1f°", wt))
                        }
                        .font(.system(size: fSize, weight: .medium))
                        .foregroundStyle(.teal)
                    }
                    if isNext {
                        Text("in \(countdownString)")
                            .font(.system(size: fSize, weight: .semibold,
                                          design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                .position(x: cx, y: cy - labelR - topOffset)
            }

            if let lt = cycleLowTide {
                let isNext = (lt.id == nextEvent?.id)
                VStack(spacing: 2) {
                    Text(hm(lt.adjustedTime))
                        .font(.system(size: fSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.08))
                    Text(viewModel.displayHeightFormatted(lt.height))
                        .font(.system(size: fSize, weight: .regular))
                        .foregroundStyle(Color(white: 0.18))
                    if let wt = waterTemp(near: lt) {
                        HStack(spacing: 3) {
                            Image(systemName: "thermometer.medium")
                            Text(String(format: "%.1f°", wt))
                        }
                        .font(.system(size: fSize, weight: .medium))
                        .foregroundStyle(.teal)
                    }
                    if isNext {
                        Text("in \(countdownString)")
                            .font(.system(size: fSize, weight: .semibold,
                                          design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                .position(x: cx, y: cy + labelR)
            }
        }
    }
}

// MARK: - Triangle shape helper

private struct TideTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
