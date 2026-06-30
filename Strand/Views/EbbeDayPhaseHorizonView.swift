import SwiftUI

/// Horizont-Bogen in der Mitte von Vorschau-Ebbe-Seiten (Tageszeit der Ebbe).
struct EbbeDayPhaseHorizonView: View {
    let ebbeTime: Date
    /// Gezeitentag wie in Tab „Tabelle“ (`TideDay.date` / `TideEvent.date`).
    let referenceDay: Date

    private var phase: EbbeDayPhase {
        EbbeDayPhase.classify(ebbeTime: ebbeTime, referenceDay: referenceDay)
    }

    private var isNight: Bool {
        phase.isNight
    }

    var body: some View {
        Canvas { ctx, size in
            drawScene(ctx: &ctx, size: size)
        }
        .clipShape(Circle())
        .aspectRatio(1, contentMode: .fit)
    }

    private func drawScene(ctx: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - side) * 0.5,
            y: (size.height - side) * 0.5
        )
        let circle = CGRect(origin: origin, size: CGSize(width: side, height: side))
        ctx.clip(to: Path(ellipseIn: circle))

        let w = side
        let h = side
        let horizonY = h * EbbeDayPhase.arcCenterFraction
        let arcRadius = w * EbbeDayPhase.arcRadiusFraction
        let arcCenter = CGPoint(x: origin.x + w * 0.5, y: origin.y + horizonY)
        let sunRadius = w * EbbeDayPhase.sunRadiusFraction

        let skyRect = CGRect(x: origin.x, y: origin.y, width: w, height: horizonY)
        ctx.fill(
            Path(skyRect),
            with: .linearGradient(
                skyGradient(),
                startPoint: CGPoint(x: origin.x + w * 0.5, y: origin.y),
                endPoint: CGPoint(x: origin.x + w * 0.5, y: origin.y + horizonY)
            )
        )

        if isNight {
            drawStars(ctx: &ctx, origin: origin, width: w, height: h, horizonY: horizonY)
        }

        if !isNight {
            let pos = EbbeDayPhase.celestialFraction(
                ebbeTime: ebbeTime,
                phase: phase,
                referenceDay: referenceDay
            )
            let center = CGPoint(x: origin.x + w * pos.x, y: origin.y + h * pos.y)
            drawSun(ctx: &ctx, center: center, radius: sunRadius, phase: phase)
        }

        ctx.fill(
            Path(CGRect(x: origin.x, y: origin.y + horizonY, width: w, height: h - horizonY)),
            with: .linearGradient(
                isNight ? nightWaterGradient() : dayWaterGradient(),
                startPoint: CGPoint(x: origin.x + w * 0.5, y: origin.y + horizonY),
                endPoint: CGPoint(x: origin.x + w * 0.5, y: origin.y + h)
            )
        )

        drawHorizonArc(
            ctx: &ctx,
            arcCenter: arcCenter,
            arcRadius: arcRadius,
            width: w,
            night: isNight
        )

        if isNight {
            let pos = EbbeDayPhase.celestialFraction(
                ebbeTime: ebbeTime,
                phase: phase,
                referenceDay: referenceDay
            )
            let center = CGPoint(x: origin.x + w * pos.x, y: origin.y + h * pos.y)
            drawSubmergedSun(ctx: &ctx, center: center, radius: sunRadius)
        }
    }

    private func drawHorizonArc(
        ctx: inout GraphicsContext,
        arcCenter: CGPoint,
        arcRadius: CGFloat,
        width w: CGFloat,
        night: Bool
    ) {
        let lineWidth = max(1.5, w * 0.016)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        var upperArc = Path()
        upperArc.addArc(
            center: arcCenter,
            radius: arcRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        ctx.stroke(
            upperArc,
            with: .color(Color(red: 0.42, green: 0.58, blue: 0.38)),
            style: style
        )

        if night {
            var lowerArc = Path()
            lowerArc.addArc(
                center: arcCenter,
                radius: arcRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(180),
                clockwise: false
            )
            ctx.stroke(
                lowerArc,
                with: .color(Color(red: 0.88, green: 0.48, blue: 0.28).opacity(0.55)),
                style: style
            )
        }
    }

    private func drawStars(
        ctx: inout GraphicsContext,
        origin: CGPoint,
        width w: CGFloat,
        height h: CGFloat,
        horizonY: CGFloat
    ) {
        let specs: [(x: CGFloat, y: CGFloat, r: CGFloat, alpha: Double)] = [
            (0.12, 0.14, 0.012, 0.85), (0.28, 0.22, 0.009, 0.65), (0.44, 0.10, 0.011, 0.75),
            (0.58, 0.18, 0.008, 0.60), (0.72, 0.12, 0.010, 0.80), (0.86, 0.24, 0.009, 0.55),
            (0.20, 0.34, 0.007, 0.50), (0.50, 0.30, 0.010, 0.70), (0.78, 0.38, 0.008, 0.60),
            (0.35, 0.08, 0.006, 0.45), (0.65, 0.06, 0.007, 0.50), (0.92, 0.08, 0.006, 0.40)
        ]
        for star in specs where star.y * h < horizonY - 4 {
            let px = origin.x + w * star.x
            let py = origin.y + h * star.y
            let r = w * star.r
            ctx.fill(
                Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                with: .color(.white.opacity(star.alpha))
            )
        }
    }

    private func drawSubmergedSun(
        ctx: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        let glow = Path(ellipseIn: CGRect(
            x: center.x - radius * 1.8,
            y: center.y - radius * 1.8,
            width: radius * 3.6,
            height: radius * 3.6
        ))
        ctx.fill(glow, with: .color(Color(red: 1.0, green: 0.45, blue: 0.18).opacity(0.22)))

        let disc = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        ctx.fill(disc, with: .color(Color(red: 0.95, green: 0.42, blue: 0.20).opacity(0.85)))
    }

    private func dayWaterGradient() -> Gradient {
        Gradient(colors: [
            Color(red: 0.48, green: 0.74, blue: 0.90).opacity(0.92),
            Color(red: 0.40, green: 0.66, blue: 0.86).opacity(0.96)
        ])
    }

    private func nightWaterGradient() -> Gradient {
        Gradient(colors: [
            Color(red: 0.72, green: 0.38, blue: 0.26).opacity(0.45),
            Color(red: 0.48, green: 0.62, blue: 0.82).opacity(0.88),
            Color(red: 0.36, green: 0.54, blue: 0.76).opacity(0.94)
        ])
    }

    private func skyGradient() -> Gradient {
        switch phase {
        case .beforeSunrise, .afterSunset:
            return Gradient(colors: [
                Color(red: 0.05, green: 0.08, blue: 0.22),
                Color(red: 0.12, green: 0.18, blue: 0.38),
                Color(red: 0.28, green: 0.16, blue: 0.22).opacity(0.55)
            ])
        case .morning:
            return Gradient(colors: [
                Color(red: 0.45, green: 0.68, blue: 0.95),
                Color(red: 0.98, green: 0.78, blue: 0.52)
            ])
        case .afternoon:
            return Gradient(colors: [
                Color(red: 0.35, green: 0.62, blue: 0.94),
                Color(red: 0.78, green: 0.90, blue: 0.98)
            ])
        case .evening:
            return Gradient(colors: [
                Color(red: 0.92, green: 0.58, blue: 0.38),
                Color(red: 0.55, green: 0.72, blue: 0.94)
            ])
        }
    }

    private func drawSun(
        ctx: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        phase: EbbeDayPhase
    ) {
        let core: Color
        switch phase {
        case .morning: core = Color(red: 1.0, green: 0.78, blue: 0.35)
        case .evening: core = Color(red: 1.0, green: 0.55, blue: 0.22)
        default: core = Color(red: 1.0, green: 0.88, blue: 0.32)
        }

        let glow = Path(ellipseIn: CGRect(
            x: center.x - radius * 1.45,
            y: center.y - radius * 1.45,
            width: radius * 2.9,
            height: radius * 2.9
        ))
        ctx.fill(glow, with: .color(core.opacity(0.25)))

        let disc = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        ctx.fill(disc, with: .color(core))
    }
}
