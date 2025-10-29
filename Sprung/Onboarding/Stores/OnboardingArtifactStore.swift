import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class OnboardingArtifactStore {
    private let modelContext: ModelContext
    private var cachedArtifacts = OnboardingArtifacts()

    init(context: ModelContext) {
        self.modelContext = context
    }

    func artifacts() -> OnboardingArtifacts {
        cachedArtifacts
    }

    func save(_ artifacts: OnboardingArtifacts) {
        cachedArtifacts = artifacts
    }

    func reset() {
        cachedArtifacts = OnboardingArtifacts()
    }
}
