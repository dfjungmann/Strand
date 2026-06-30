import SwiftUI
import WidgetKit

/// Gefülltes Ringsegment für den Strandy-Bogen (Uhrwinkel: 0° = oben, 180° = unten).
private struct StrandyArcBand: Shape {
    var startClockAngleDeg: Double
    var endClockAngleDeg: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxR = min(rect.width, rect.height) * 0.48
        let outerR = maxR * 0.72
        let innerR = maxR * 0.52
        let start = Angle.degrees(startClockAngleDeg - 90.0)
        let end = Angle.degrees(endClockAngleDeg - 90.0)

        var path = Path()
        path.addArc(center: center, radius: outerR,
                    startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerR,
                    startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Volle Strand-Gezeiten-Uhr für Watch-Komplikationen (Variante C — maximal).
struct TideComplicationDialView: View {
    let now: Date
    let events: [TideEvent]
    var hasData: Bool = true

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var clock: TideClockState {
        TideClockState(now: now, events: events)
    }

    private let markerBlue = Color(red: 0.35, green: 0.55, blue: 0.82)
    private let goldRing = Color(red: 0.88, green: 0.72, blue: 0.22)
    private let needleRed = Color(red: 0.88, green: 0.12, blue: 0.10)

    /// Vollfarbe / Vibrant (Ultra, Infograph …) — accessoryCircular unterstützt kein echtes fullColor laut Doku, Ultra nutzt oft .vibrant.
    private var colorful: Bool {
        renderingMode == .fullColor || renderingMode == .vibrant
    }

    private var showStrandyArc: Bool {
        clock.strandyArcWindow != nil
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let r = s * 0.48

            ZStack {
                if hasData {
                    rings(size: s)
                    if showStrandyArc { strandyArc(size: s) }
                    tickMarks(size: s)
                    markers(size: s)
                    if colorful {
                        needleRotated(size: s, radius: r)
                    } else {
                        needleCanvas(cx: cx, cy: cy, r: r)
                    }
                } else {
                    Circle()
                        .strokeBorder(.secondary.opacity(0.4), lineWidth: 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private func rings(size s: CGFloat) -> some View {
        Circle()
            .strokeBorder(ringColor(gray: 0.55), lineWidth: max(2, s * 0.055))
        Circle()
            .inset(by: s * 0.065)
            .stroke(colorful ? goldRing : ringColor(gray: 0.70), lineWidth: max(1.5, s * 0.04))
        Circle()
            .inset(by: s * 0.10)
            .stroke(ringColor(gray: 0.62), lineWidth: max(1, s * 0.03))
    }

    @ViewBuilder
    private func strandyArc(size s: CGFloat) -> some View {
        if let arc = clock.strandyArcWindow {
            if colorful {
                StrandyArcBand(
                    startClockAngleDeg: arc.startClockAngleDeg,
                    endClockAngleDeg: arc.endClockAngleDeg
                )
                .fill(
                    TideBeachWalk.strandyArcAngularGradient(
                        startClockAngleDeg: arc.startClockAngleDeg,
                        endClockAngleDeg: arc.endClockAngleDeg,
                        heightAtFraction: { fraction in
                            let span = arc.endTime.timeIntervalSince(arc.startTime)
                            let t = arc.startTime.addingTimeInterval(span * fraction)
                            return clock.height(at: t) ?? 0
                        }
                    )
                )
                .widgetAccentable(false)
            } else {
                StrandyArcBand(
                    startClockAngleDeg: arc.startClockAngleDeg,
                    endClockAngleDeg: arc.endClockAngleDeg
                )
                .fill(Color.primary.opacity(0.55))
                .widgetAccentable(true)
            }
        }
    }

    @ViewBuilder
    private func tickMarks(size s: CGFloat) -> some View {
        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
            Rectangle()
                .fill(Color.primary.opacity(0.55))
                .frame(width: max(1, s * 0.025), height: s * 0.055)
                .offset(y: -s * 0.36)
                .rotationEffect(.degrees(Double(minute) / 60.0 * 360.0))
        }
    }

    @ViewBuilder
    private func markers(size s: CGFloat) -> some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: s * 0.11, weight: .bold))
            .foregroundStyle(colorful ? markerBlue : .primary.opacity(0.7))
            .offset(y: -s * 0.38)

        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: s * 0.11, weight: .bold))
            .foregroundStyle(colorful ? markerBlue : .primary.opacity(0.7))
            .offset(y: s * 0.38)
    }

    /// Zeiger per SwiftUI-Rotation — korrekt auf Vollfarbe-/Vibrant-Ziffernblättern (Ultra).
    @ViewBuilder
    private func needleRotated(size s: CGFloat, radius r: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(needleRed)
                .widgetAccentable(false)
                .frame(width: max(2.5, s * 0.048), height: r * 0.70)
                .offset(y: -r * 0.35)

            RoundedRectangle(cornerRadius: 1)
                .fill(needleRed)
                .widgetAccentable(false)
                .frame(width: s * 0.15, height: max(3, s * 0.075))
                .offset(y: -r * 0.58)

            Circle()
                .fill(needleRed)
                .widgetAccentable(false)
                .frame(width: max(4, s * 0.09), height: max(4, s * 0.09))
        }
        .rotationEffect(.degrees(clock.needleAngleDeg))
    }

    /// Zeiger per Canvas — korrekt auf Akzent-Ziffernblättern (Modular Duo).
    @ViewBuilder
    private func needleCanvas(cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Canvas { ctx, _ in
            let angle = clock.needleAngleDeg
            let rad = (angle - 90.0) * .pi / 180.0
            let perp = rad + .pi / 2
            let tabCx = r * 0.66
            let hLen = r * 0.085
            let hWid = r * 0.048
            let tabCenter = CGPoint(x: cx + tabCx * cos(rad), y: cy + tabCx * sin(rad))

            let lineEnd = tabCx - hLen
            let tip = CGPoint(x: cx + lineEnd * cos(rad), y: cy + lineEnd * sin(rad))
            var line = Path()
            line.move(to: CGPoint(x: cx, y: cy))
            line.addLine(to: tip)

            ctx.stroke(line, with: .color(Color.primary),
                       style: StrokeStyle(lineWidth: max(3.0, r * 0.038), lineCap: .butt))

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
            ctx.fill(tab, with: .color(.primary))

            let dotR = max(3.0, r * 0.022)
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
                with: .color(.primary)
            )
        }
        .allowsHitTesting(false)
    }

    private func ringColor(gray: Double) -> Color {
        colorful ? Color(white: gray) : Color.primary.opacity(0.35)
    }
}
