import SwiftUI

/// Horizont-Bogen in der Mitte von Vorschau-Ebbe-Seiten (Tageszeit der Ebbe).
struct EbbeDayPhaseHorizonView: View {
    let ebbeTime: Date
    var labelFontSize: CGFloat = 13

    private var astronomy: AstronomyData {
        AstronomyService.data(for: ebbeTime)
    }

    private var phase: EbbeDayPhase {
        EbbeDayPhase.classify(ebbeTime: ebbeTime, astronomy: astronomy)
    }

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                drawScene(ctx: &ctx, size: size)
            }
            .aspectRatio(1.15, contentMode: .fit)

            Text(phase.rawValue)
                .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.38))
                .multilineTextAlignment(.center)
        }
    }

    private func drawScene(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let horizonY = h * 0.72
        let arcRadius = w * 0.40
        let arcCenter = CGPoint(x: w * 0.5, y: horizonY)

        // Himmel
        let skyRect = CGRect(x: 0, y: 0, width: w, height: horizonY)
        ctx.fill(
            Path(skyRect),
            with: .linearGradient(
                skyGradient(),
                startPoint: CGPoint(x: w * 0.5, y: 0),
                endPoint: CGPoint(x: w * 0.5, y: horizonY)
            )
        )

        // Wasser unter dem Horizont
        ctx.fill(
            Path(CGRect(x: 0, y: horizonY, width: w, height: h - horizonY)),
            with: .color(Color(red: 0.55, green: 0.78, blue: 0.92).opacity(0.55))
        )

        // Horizont-Bogen
        var horizon = Path()
        horizon.addArc(
            center: arcCenter,
            radius: arcRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        ctx.stroke(
            horizon,
            with: .color(Color(red: 0.42, green: 0.58, blue: 0.38)),
            style: StrokeStyle(lineWidth: max(1.5, w * 0.018), lineCap: .round)
        )

        let pos = EbbeDayPhase.celestialFraction(
            ebbeTime: ebbeTime,
            phase: phase,
            astronomy: astronomy
        )
        let bodyCenter = CGPoint(x: w * pos.x, y: h * pos.y)
        let bodyR = w * 0.065

        switch phase {
        case .beforeSunrise, .afterSunset:
            drawMoon(ctx: &ctx, center: bodyCenter, radius: bodyR)
        case .morning, .afternoon, .evening:
            drawSun(ctx: &ctx, center: bodyCenter, radius: bodyR, phase: phase)
        }
    }

    private func skyGradient() -> Gradient {
        switch phase {
        case .beforeSunrise:
            return Gradient(colors: [
                Color(red: 0.08, green: 0.12, blue: 0.28),
                Color(red: 0.18, green: 0.28, blue: 0.48)
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
        case .afterSunset:
            return Gradient(colors: [
                Color(red: 0.10, green: 0.14, blue: 0.32),
                Color(red: 0.28, green: 0.22, blue: 0.42)
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

    private func drawMoon(ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let disc = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        ctx.fill(disc, with: .color(Color(red: 0.88, green: 0.90, blue: 0.96)))

        // Sichel-Schatten
        let shadow = Path(ellipseIn: CGRect(
            x: center.x - radius * 0.55,
            y: center.y - radius * 1.05,
            width: radius * 1.7,
            height: radius * 1.7
        ))
        ctx.fill(shadow, with: .color(Color(red: 0.12, green: 0.16, blue: 0.30).opacity(0.55)))
    }
}
