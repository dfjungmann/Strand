import SwiftUI

/// DSEG7 Classic — 7-Segment-Anzeige (Flip-Uhr-Optik), SIL OFL 1.1 · keshikan/DSEG
enum FlipClockFont {
    static let postScriptName = "DSEG7Classic-Bold"

    static func time(size: CGFloat) -> Font {
        .custom(postScriptName, size: size)
    }
}
