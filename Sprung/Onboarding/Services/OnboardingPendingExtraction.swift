@preconcurrency import SwiftyJSON

struct OnboardingPendingExtraction: @unchecked Sendable {
    var rawExtraction: JSON
    var uncertainties: [String]
}
