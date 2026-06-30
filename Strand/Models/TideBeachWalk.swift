import Foundation
import SwiftUI

/// Strandy-Schwellwerte und Farblogik (iPhone + Watch).
enum TideBeachWalk {
    static var thresholdSafe: Double {
        UserDefaults.standard.object(forKey: TideSettingsKeys.beachWalkThresholdSafe) as? Double ?? 0.55
    }

    static var thresholdLikely: Double {
        UserDefaults.standard.object(forKey: TideSettingsKeys.beachWalkThresholdLikely) as? Double ?? 0.65
    }

    static var deepCm: Int {
        UserDefaults.standard.object(forKey: TideSettingsKeys.beachWalkDeepCm) as? Int ?? 7
    }

    static func apply(to days: [TideDay]) -> [TideDay] {
        days.map { day in
            var updated = day
            updated.events = day.events.map { event in
                var e = event
                guard event.type == .lowTide else {
                    e.beachWalkStatus = .none
                    return e
                }
                if event.height <= thresholdSafe {
                    e.beachWalkStatus = .safe
                } else if event.height <= thresholdLikely {
                    e.beachWalkStatus = .likely
                } else {
                    e.beachWalkStatus = .none
                }
                return e
            }
            return updated
        }
    }

    /// Hintergrund- und Textfarbe (wie TideViewModel.beachWalkGradientColors).
    static func gradientColors(rawHeight: Double) -> (background: Color, text: Color) {
        let safe = thresholdSafe
        let likely = thresholdLikely
        if rawHeight > likely {
            return (.clear, .primary)
        }

        if rawHeight > safe {
            let range = max(likely - safe, 0.001)
            let t = (rawHeight - safe) / range
            let hue = 0.167 + (1.0 - t) * (0.333 - 0.167)
            let saturation = 0.55 + (1.0 - t) * 0.20
            return (Color(hue: hue, saturation: saturation, brightness: 0.92), .black)
        }

        let deepThreshold = safe - Double(deepCm) / 100.0

        if rawHeight > deepThreshold {
            let range = max(safe - deepThreshold, 0.001)
            let t = (safe - rawHeight) / range
            let saturation = 0.38 + t * 0.27
            let brightness = 0.90 - t * 0.05
            return (Color(hue: 0.333, saturation: saturation, brightness: brightness), .black)
        }

        let depth = min(deepThreshold - rawHeight, 0.20)
        let t = depth / 0.20
        let saturation = 0.80 + t * 0.15
        let brightness = 0.52 - t * 0.12
        return (Color(hue: 0.333, saturation: saturation, brightness: brightness), .white)
    }

    /// Deckende RGB-Farbe für den Strandy-Bogen (Komplikation — nicht hue-basiert).
    static func strandyArcFillColor(rawHeight: Double, status: BeachWalkStatus) -> Color {
        guard status != .none else { return .clear }
        let safe = thresholdSafe
        let likely = thresholdLikely

        if status == .likely || rawHeight > safe {
            let range = max(likely - safe, 0.001)
            let t = min(1, max(0, (rawHeight - safe) / range))
            // Gelb → Gelbgrün
            return Color(
                red: 0.78 + (1 - t) * 0.02,
                green: 0.84 - (1 - t) * 0.06,
                blue: 0.30 + (1 - t) * 0.10
            )
        }

        let deepThreshold = safe - Double(deepCm) / 100.0
        if rawHeight > deepThreshold {
            let range = max(safe - deepThreshold, 0.001)
            let t = (safe - rawHeight) / range
            return Color(
                red: 0.38 + t * 0.04,
                green: 0.80 - t * 0.04,
                blue: 0.40 + t * 0.02
            )
        }

        return Color(red: 0.28, green: 0.68, blue: 0.32)
    }

    /// Farbe für den Strandy-Bogen (Komplikation + App).
    static func strandyArcColor(rawHeight: Double, status: BeachWalkStatus) -> Color {
        guard status != .none else { return .clear }
        let bg = gradientColors(rawHeight: rawHeight).background
        if bg != .clear { return bg }
        switch status {
        case .safe:   return Color(hue: 0.333, saturation: 0.55, brightness: 0.88)
        case .likely: return Color(hue: 0.167, saturation: 0.55, brightness: 0.90)
        case .none:   return .clear
        }
    }

    static func beachWalkStatus(forHeight rawHeight: Double) -> BeachWalkStatus {
        if rawHeight <= thresholdSafe { return .safe }
        if rawHeight <= thresholdLikely { return .likely }
        return .none
    }

    private static func strandyArcSegmentColor(
        rawHeight: Double,
        useFillColors: Bool
    ) -> Color {
        if useFillColors {
            return strandyArcFillColor(
                rawHeight: rawHeight,
                status: beachWalkStatus(forHeight: rawHeight)
            )
        }
        return gradientColors(rawHeight: rawHeight).background
    }

    /// Farbverlauf entlang des Strandy-Bogens (Uhrwinkel 0° = Flut oben, 180° = Ebbe unten).
    static func strandyArcAngularGradient(
        startClockAngleDeg: Double,
        endClockAngleDeg: Double,
        heightAtFraction: (Double) -> Double,
        opacity: Double = 0.88,
        useFillColors: Bool = true,
        segmentCount: Int = 16
    ) -> AngularGradient {
        let stops = (0...segmentCount).map { i -> Gradient.Stop in
            let fraction = Double(i) / Double(segmentCount)
            let color = strandyArcSegmentColor(
                rawHeight: heightAtFraction(fraction),
                useFillColors: useFillColors
            )
            let alpha = color == .clear ? 0 : opacity
            return Gradient.Stop(color: color.opacity(alpha), location: fraction)
        }
        return AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center,
            startAngle: .degrees(startClockAngleDeg - 90.0),
            endAngle: .degrees(endClockAngleDeg - 90.0)
        )
    }

    /// Strandy-Bogen als segmentierter Stroke (Watch-/Canvas-Uhr).
    static func drawStrandyArcStroke(
        _ ctx: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        arcRadius: CGFloat,
        startClockAngleDeg: Double,
        endClockAngleDeg: Double,
        lineWidth: CGFloat,
        heightAtFraction: (Double) -> Double,
        opacity: Double = 0.75,
        useFillColors: Bool = false,
        segmentCount: Int = 20
    ) {
        let startDeg = startClockAngleDeg - 90.0
        let endDeg = endClockAngleDeg - 90.0
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)

        for i in 0..<segmentCount {
            let f0 = Double(i) / Double(segmentCount)
            let f1 = Double(i + 1) / Double(segmentCount)
            let color = strandyArcSegmentColor(
                rawHeight: heightAtFraction((f0 + f1) / 2.0),
                useFillColors: useFillColors
            )
            guard color != .clear else { continue }

            let a0 = startDeg + f0 * (endDeg - startDeg)
            let a1 = startDeg + f1 * (endDeg - startDeg)
            var arc = Path()
            arc.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: arcRadius,
                startAngle: .degrees(a0),
                endAngle: .degrees(a1),
                clockwise: false
            )
            ctx.stroke(arc, with: .color(color.opacity(opacity)), style: style)
        }
    }
}
