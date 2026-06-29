import Foundation

enum TideSettingsKeys {
    static let tideReferenceOffsetCm = "tide_reference_offset_cm"
    static let timeOffsetMinutes = "timeOffsetMinutes"
    static let beachWalkThresholdSafe = "beachWalkThresholdSafe"
    static let beachWalkThresholdLikely = "beachWalkThresholdLikely"
    static let beachWalkDeepCm = "beachWalkDeepCm"

    static let watchSyncKeys = [
        tideReferenceOffsetCm,
        timeOffsetMinutes,
        beachWalkThresholdSafe,
        beachWalkThresholdLikely,
        beachWalkDeepCm,
    ]
}
