import SwiftUI

// MARK: - Tide Clock View

struct TideClockView: View {
    let viewModel: TideViewModel
    @Binding var selectedTab: Int

    private let showTideHeightOnNeedle = true
    private let useFlipClockFont = true

    @State private var now = Date()
    @State private var selectedPageIndex = 0
    @State private var followLivePage = true
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var allEvents: [TideEvent] {
        viewModel.tideDays
            .flatMap { $0.events }
            .sorted { $0.adjustedTime < $1.adjustedTime }
    }

    private var clockState: TideClockState {
        TideClockState(now: now, events: allEvents)
    }

    private var ebbePages: [TideClockState.TideEbbePage] {
        clockState.ebbeSwipePages
    }

    private var livePageIndex: Int {
        clockState.activeLiveEbbePageIndex ?? 0
    }

    private var prevEvent: TideEvent? { allEvents.last { $0.adjustedTime <= now } }
    private var nextEvent: TideEvent? { allEvents.first { $0.adjustedTime > now } }

    private var cycleProgress: Double {
        guard let p = prevEvent, let n = nextEvent else { return 0 }
        let elapsed = now.timeIntervalSince(p.adjustedTime)
        let total = n.adjustedTime.timeIntervalSince(p.adjustedTime)
        return max(0, min(1, elapsed / total))
    }

    private var needleAngleDeg: Double {
        guard let p = prevEvent else { return 0 }
        return p.type == .highTide
            ? cycleProgress * 180.0
            : 180.0 + cycleProgress * 180.0
    }

    private var currentHeight: Double {
        guard let p = prevEvent, let n = nextEvent else { return 0 }
        let h0 = p.height, h1 = n.height
        return (h0 + h1) / 2.0 + (h0 - h1) / 2.0 * cos(.pi * cycleProgress)
    }

    private var nextIsHigh: Bool { nextEvent?.type == .highTide }

    private var countdownString: String { clockState.countdownString }

    private var tz: TimeZone { TideService.canaryIslandsTimeZone }

    private func hh(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH"; f.timeZone = tz
        return f.string(from: date)
    }

    private func mm(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "mm"; f.timeZone = tz
        return f.string(from: date)
    }

    private func hm(_ date: Date) -> String { "\(hh(date)):\(mm(date))" }

    private func clockTimeFont(size: CGFloat) -> Font {
        if useFlipClockFont {
            return FlipClockFont.time(size: size)
        }
        return .system(size: size, weight: .black, design: .monospaced)
    }

    private func waterTemp(near event: TideEvent) -> Double? {
        viewModel.hourlyMarine
            .min(by: { abs($0.time.timeIntervalSince(event.adjustedTime))
                     < abs($1.time.timeIntervalSince(event.adjustedTime)) })?
            .waterTemp
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 0.82, green: 0.91, blue: 0.97).ignoresSafeArea()

            if viewModel.tideDays.isEmpty {
                ProgressView("Lade…").tint(.white).foregroundStyle(.white)
            } else if ebbePages.isEmpty {
                Text("Keine Gezeitendaten")
                    .foregroundStyle(Color(white: 0.2))
            } else {
                TabView(selection: $selectedPageIndex) {
                    ForEach(Array(ebbePages.enumerated()), id: \.element.id) { index, page in
                        tideClockPage(page: page, isLive: index == livePageIndex)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selectedPageIndex) { _, newIndex in
                    followLivePage = (newIndex == livePageIndex)
                }
            }
        }
        .onAppear {
            followLivePage = true
            syncToLivePage(animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clockTabReselected)) { _ in
            followLivePage = true
            syncToLivePage(animated: true)
        }
        .onReceive(timer) { tick in
            now = tick
            if followLivePage {
                syncToLivePage(animated: true)
            }
        }
    }

    private func syncToLivePage(animated: Bool) {
        let target = livePageIndex
        guard target != selectedPageIndex else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                selectedPageIndex = target
            }
        } else {
            selectedPageIndex = target
        }
    }

    // MARK: - Single page

    @ViewBuilder
    private func tideClockPage(page: TideClockState.TideEbbePage, isLive: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = min(w, h) * 0.44
            let cx = w / 2
            let cy = h / 2

            ZStack {
                clockFaceCanvas(page: page, cx: cx, cy: cy, r: r)
                if isLive {
                    needleCanvas(cx: cx, cy: cy, r: r)
                    if showTideHeightOnNeedle {
                        needleHeightLabel(cx: cx, cy: cy, r: r)
                    }
                    centerReadout(cx: cx, cy: cy, r: r)
                } else {
                    EbbeDayPhaseHorizonView(
                        ebbeTime: page.lowTide.adjustedTime,
                        referenceDay: page.lowTide.date
                    )
                        .frame(width: r * 1.26, height: r * 1.26)
                        .position(x: cx, y: cy)
                }
                tideMarkerViews(cx: cx, cy: cy, r: r)
                if isLive {
                    liveOuterLabels(cx: cx, cy: cy, r: r)
                } else {
                    previewOuterLabels(page: page, width: w, cx: cx, cy: cy, r: r)
                }
            }
        }
    }

    // MARK: - Clock face (Canvas)

    @ViewBuilder
    private func clockFaceCanvas(
        page: TideClockState.TideEbbePage,
        cx: CGFloat,
        cy: CGFloat,
        r: CGFloat
    ) -> some View {
        Canvas { ctx, _ in
            fillRing(ctx, cx, cy, r * 0.87, r, Color(white: 0.74))
            fillRing(ctx, cx, cy, r * 0.81, r * 0.87, Color(red: 0.88, green: 0.72, blue: 0.22))
            fillRing(ctx, cx, cy, r * 0.76, r * 0.81, Color(white: 0.68))
            fillRing(ctx, cx, cy, r * 0.65, r * 0.76, Color(red: 0.93, green: 0.96, blue: 0.99))

            if let arc = clockState.strandyArcWindow(for: page.lowTide) {
                TideBeachWalk.drawStrandyArcStroke(
                    &ctx,
                    cx: cx,
                    cy: cy,
                    arcRadius: r * 0.66,
                    startClockAngleDeg: arc.startClockAngleDeg,
                    endClockAngleDeg: arc.endClockAngleDeg,
                    lineWidth: r * 0.18,
                    heightAtFraction: { fraction in
                        let span = arc.endTime.timeIntervalSince(arc.startTime)
                        let t = arc.startTime.addingTimeInterval(span * fraction)
                        return clockState.height(at: t) ?? 0
                    }
                )
            }

            let tickOuter = r * 0.74
            for i in 0..<60 {
                let deg = Double(i) / 60.0 * 360.0 - 90.0
                let rad = deg * .pi / 180.0
                let isMajor = i % 5 == 0
                let tickLen: CGFloat = isMajor ? r * 0.070 : r * 0.038
                let lw: CGFloat = isMajor ? 2.2 : 1.0
                let p0 = CGPoint(x: cx + (tickOuter - tickLen) * cos(rad),
                                 y: cy + (tickOuter - tickLen) * sin(rad))
                let p1 = CGPoint(x: cx + tickOuter * cos(rad),
                                 y: cy + tickOuter * sin(rad))
                var lp = Path(); lp.move(to: p0); lp.addLine(to: p1)
                ctx.stroke(lp, with: .color(Color(white: 0.12).opacity(isMajor ? 0.85 : 0.35)),
                           lineWidth: lw)
            }

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

    private func fillRing(
        _ ctx: GraphicsContext,
        _ cx: CGFloat, _ cy: CGFloat,
        _ innerR: CGFloat, _ outerR: CGFloat,
        _ color: Color
    ) {
        var p = Path()
        p.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerR,
                                width: outerR * 2, height: outerR * 2))
        p.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR,
                                width: innerR * 2, height: innerR * 2))
        ctx.fill(p, with: .color(color), style: FillStyle(eoFill: true))
    }

    // MARK: - Needle (live only)

    @ViewBuilder
    private func needleCanvas(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Canvas { ctx, _ in
            let rad = (needleAngleDeg - 90.0) * .pi / 180.0
            let perp = rad + .pi / 2

            let tabCx = r * 0.66
            let hLen: CGFloat = r * 0.065
            let hWid: CGFloat = r * 0.028
            let tabCenter = CGPoint(x: cx + tabCx * cos(rad), y: cy + tabCx * sin(rad))

            let lineEnd = tabCx - hLen
            let tipLine = CGPoint(x: cx + lineEnd * cos(rad), y: cy + lineEnd * sin(rad))
            var line = Path(); line.move(to: CGPoint(x: cx, y: cy)); line.addLine(to: tipLine)
            ctx.stroke(line, with: .color(.red.opacity(0.85)),
                       style: StrokeStyle(lineWidth: max(4.0, r * 0.014), lineCap: .butt))

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

            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)),
                with: .color(.red)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var tideHeightLabelRotation: Double {
        let a = needleAngleDeg
        return (a > 90 && a < 270) ? a + 180 : a
    }

    @ViewBuilder
    private func needleHeightLabel(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let heightBlue = Color(red: 0.08, green: 0.32, blue: 0.72)
        let fSize = r * 0.175
        let rad = (needleAngleDeg - 90.0) * .pi / 180.0
        let tabR = r * 0.84
        let x = cx + tabR * cos(rad)
        let y = cy + tabR * sin(rad)

        Text(viewModel.displayHeightValueFormatted(currentHeight))
            .font(.system(size: fSize, weight: .black, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(heightBlue)
            .shadow(color: .white, radius: 2)
            .shadow(color: .white.opacity(0.8), radius: 5)
            .rotationEffect(.degrees(tideHeightLabelRotation))
            .position(x: x, y: y)
            .animation(.linear(duration: 1), value: needleAngleDeg)
    }

    // MARK: - Markers

    @ViewBuilder
    private func tideMarkerViews(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let markerR = r * 0.795
        let triSize = r * 0.13
        let blue = Color(red: 0.35, green: 0.55, blue: 0.82)

        ZStack {
            TideTriangle()
                .fill(blue)
                .frame(width: triSize, height: triSize)
                .position(x: cx, y: cy - markerR)

            TideTriangle()
                .fill(blue)
                .rotationEffect(.degrees(180))
                .frame(width: triSize, height: triSize)
                .position(x: cx, y: cy + markerR)

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

    // MARK: - Centre readout (live only)

    @ViewBuilder
    private func centerReadout(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let innerR = r * 0.64
        let fSize = innerR * 0.36
        let maxW = innerR * 1.75
        let countdownGray = Color(white: 0.38)

        VStack(spacing: r * 0.024) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(hh(now))
                    .font(clockTimeFont(size: fSize * 1.08))
                    .monospacedDigit()
                Text(":")
                    .font(clockTimeFont(size: fSize * 1.08))
                Text(mm(now))
                    .font(clockTimeFont(size: fSize * 1.08))
                    .monospacedDigit()
            }
            .foregroundStyle(.black)
            .fixedSize()

            Text("\(nextIsHigh ? "↑" : "↓")  \(countdownString)")
                .font(.system(size: fSize * 0.46, weight: .medium, design: .monospaced)
                    .monospacedDigit())
                .foregroundStyle(countdownGray)
                .offset(y: r * 0.055)
        }
        .frame(maxWidth: maxW)
        .position(x: cx, y: cy)
    }

    // MARK: - Outer labels (live)

    @ViewBuilder
    private func liveOuterLabels(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        let labelR = r * 1.22
        let topOffset = r * 0.10
        let fSize = r * 0.115

        ZStack {
            if let displayed = clockState.displayedHighTide {
                let ht = displayed.event
                VStack(spacing: 2) {
                    Text(clockState.liveTimeLabel(for: displayed))
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
                    if displayed.recency == .upcoming {
                        Text("in \(clockState.countdownString(to: ht))")
                            .font(.system(size: fSize, weight: .semibold,
                                          design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                .position(x: cx, y: cy - labelR - topOffset)
            }

            if let displayed = clockState.displayedLowTide {
                ebbeBottomBlock(
                    lowTide: displayed.event,
                    fontSize: fSize,
                    liveDisplayed: displayed
                )
                .position(x: cx, y: cy + labelR)
            }
        }
    }

    // MARK: - Ebbe unten (Live + Vorschau)

    @ViewBuilder
    private func ebbeBottomBlock(
        lowTide: TideEvent,
        fontSize: CGFloat,
        liveDisplayed: TideClockState.DisplayedTide? = nil
    ) -> some View {
        VStack(spacing: 2) {
            if let displayed = liveDisplayed {
                Text(clockState.liveTimeLabel(for: displayed))
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.08))
            } else {
                Text(clockState.previewTimeLabel(for: lowTide))
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.08))
                    .multilineTextAlignment(.center)
            }

            Text(viewModel.displayHeightFormatted(lowTide.height))
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(Color(white: 0.18))

            if let wt = waterTemp(near: lowTide) {
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                    Text(String(format: "%.1f°", wt))
                }
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.teal)
            }

            waveHeightRow(near: lowTide, fontSize: fontSize * 0.88)
            strandyTimeLabel(lowTide: lowTide, fontSize: fontSize * 0.82)
        }
    }

    @ViewBuilder
    private func waveHeightRow(near event: TideEvent, fontSize: CGFloat) -> some View {
        if let wh = viewModel.waveHeight(at: event.adjustedTime) {
            HStack(spacing: 3) {
                Image(systemName: "water.waves")
                Text(String(format: "%.1f m", wh))
            }
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.teal)
        }
    }

    @ViewBuilder
    private func strandyTimeLabel(lowTide: TideEvent, fontSize: CGFloat) -> some View {
        if let arc = clockState.strandyArcWindow(for: lowTide) {
            VStack(spacing: 1) {
                Text("Strandy:")
                Text("\(hm(arc.startTime)) → \(hm(arc.endTime))")
            }
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.22))
            .multilineTextAlignment(.center)
        } else {
            Text("Flut für Strandy zu hoch.")
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.35))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Outer labels (Vorschau — zwei Fluten oben)

    @ViewBuilder
    private func previewOuterLabels(
        page: TideClockState.TideEbbePage,
        width: CGFloat,
        cx: CGFloat,
        cy: CGFloat,
        r: CGFloat
    ) -> some View {
        let labelR = r * 1.22
        let topOffset = r * 0.10
        let fSize = r * 0.10
        let colW = width * 0.38

        ZStack {
            HStack(alignment: .top, spacing: width * 0.04) {
                if let highBefore = page.highBefore {
                    previewTideColumn(event: highBefore, fontSize: fSize)
                        .frame(width: colW)
                } else {
                    Color.clear.frame(width: colW)
                }
                if let highAfter = page.highAfter {
                    previewTideColumn(event: highAfter, fontSize: fSize)
                        .frame(width: colW)
                } else {
                    Color.clear.frame(width: colW)
                }
            }
            .frame(maxWidth: width * 0.88)
            .position(x: cx, y: cy - labelR - topOffset)

            ebbeBottomBlock(lowTide: page.lowTide, fontSize: r * 0.115)
                .position(x: cx, y: cy + labelR)
        }
    }

    @ViewBuilder
    private func previewTideColumn(event: TideEvent, fontSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(clockState.previewTimeLabel(for: event))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.08))
                .multilineTextAlignment(.center)
            Text(viewModel.displayHeightFormatted(event.height))
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(Color(white: 0.18))
            if let wt = waterTemp(near: event) {
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                    Text(String(format: "%.1f°", wt))
                }
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.teal)
            }
        }
    }
}

// MARK: - Triangle shape helper

private struct TideTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
