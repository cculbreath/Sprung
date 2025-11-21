//
//  OnboardingArtifacts.swift
//  Sprung
//
//  Domain model for onboarding artifacts.
//

import Foundation
import SwiftyJSON

struct OnboardingArtifacts {
    var applicantProfile: JSON?
    var skeletonTimeline: JSON?
    var enabledSections: Set<String> = []
    var experienceCards: [JSON] = []
    var writingSamples: [JSON] = []
    var artifactRecords: [JSON] = []
    var knowledgeCards: [JSON] = [] // Phase 3: Knowledge card storage
}
