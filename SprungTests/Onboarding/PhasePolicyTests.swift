//
//  PhasePolicyTests.swift
//  SprungTests
//
//  Tests for the pure phase/tool policy seams that are testable without constructing
//  the StateCoordinator actor or the full coordinator graph:
//
//   • ToolBundlePolicy — all static, pure functions over (phase, subphase, objectives,
//     UI card). Single source of truth for tool availability. We assert the structural
//     invariants documented in the file (escape tools always present, artifact tools
//     gated to Phase 2-4, filesystem tools gated to Phase 3, phase union ⊇ every
//     subphase bundle) plus subphase inference and dispatch-time gating.
//   • PhaseScript.canAdvance / missingObjectives — the default protocol logic over the
//     concrete phase scripts (plain structs, no-arg init).
//
//  StateCoordinator / PhaseTransitionService are intentionally NOT exercised here —
//  they require a SwiftData + multi-store graph that is not cleanly constructible in a
//  unit test (see the Phase 4 report).
//

import XCTest
@testable import Sprung

final class PhasePolicyTests: XCTestCase {

    // MARK: - Safe-escape tools are always available

    func testSafeEscapeToolsPresentInEveryPhase() {
        for phase in InterviewPhase.allCases {
            let allowed = ToolBundlePolicy.allowedToolsForPhase(phase)
            XCTAssertTrue(ToolBundlePolicy.safeEscapeTools.isSubset(of: allowed),
                          "safe escape tools must be available in \(phase.rawValue)")
        }
    }

    func testSafeEscapeToolsPresentInEverySubphaseAvailability() {
        for subphase in InterviewSubphase.allCases {
            let available = ToolBundlePolicy.availableTools(in: subphase)
            XCTAssertTrue(ToolBundlePolicy.safeEscapeTools.isSubset(of: available),
                          "safe escape tools must be executable in \(subphase.rawValue)")
        }
    }

    // MARK: - Artifact / filesystem gating by phase

    func testArtifactToolsGatedToPhase2Through4() {
        // Phase 1 excludes artifact-access tools; Phases 2-4 include them.
        let p1 = ToolBundlePolicy.allowedToolsForPhase(.phase1VoiceContext)
        XCTAssertTrue(ToolBundlePolicy.artifactAccessTools.isDisjoint(with: p1),
                      "Phase 1 must NOT carry artifact-access tools")

        for phase in [InterviewPhase.phase2CareerStory, .phase3EvidenceCollection, .phase4StrategicSynthesis] {
            let allowed = ToolBundlePolicy.allowedToolsForPhase(phase)
            XCTAssertTrue(ToolBundlePolicy.artifactAccessTools.isSubset(of: allowed),
                          "\(phase.rawValue) must carry artifact-access tools")
        }
    }

    func testFilesystemBrowsingToolsOnlyInPhase3() {
        for phase in InterviewPhase.allCases {
            let allowed = ToolBundlePolicy.allowedToolsForPhase(phase)
            if phase == .phase3EvidenceCollection {
                XCTAssertTrue(ToolBundlePolicy.filesystemBrowsingTools.isSubset(of: allowed),
                              "Phase 3 must carry filesystem-browsing tools")
            } else {
                XCTAssertTrue(ToolBundlePolicy.filesystemBrowsingTools.isDisjoint(with: allowed),
                              "\(phase.rawValue) must NOT carry filesystem-browsing tools")
            }
        }
    }

    // MARK: - Phase union ⊇ every subphase bundle (derivation invariant)

    /// The file documents that phase-level permissions are the union of all the phase's
    /// subphase bundles. Verify the derivation holds for every subphase.
    func testPhaseUnionContainsEverySubphaseBundle() {
        for subphase in InterviewSubphase.allCases {
            let phaseAllowed = ToolBundlePolicy.allowedToolsForPhase(subphase.phase)
            let bundle = ToolBundlePolicy.subphaseBundles[subphase] ?? []
            XCTAssertTrue(bundle.isSubset(of: phaseAllowed),
                          "tools in \(subphase.rawValue) must all be allowed in \(subphase.phase.rawValue)")
            // And the per-subphase dispatch set is itself a subset of the phase union
            // (it only adds escape/artifact/filesystem tools the phase union also has).
            let available = ToolBundlePolicy.availableTools(in: subphase)
            XCTAssertTrue(available.isSubset(of: phaseAllowed),
                          "available(\(subphase.rawValue)) must be within the \(subphase.phase.rawValue) union")
        }
    }

    func testPrecomputedAllowedByPhaseMatchesComputed() throws {
        for phase in InterviewPhase.allCases {
            let precomputed = try XCTUnwrap(ToolBundlePolicy.allowedToolsByPhase[phase],
                                            "precomputed table must have an entry for \(phase.rawValue)")
            XCTAssertEqual(precomputed,
                           ToolBundlePolicy.allowedToolsForPhase(phase),
                           "precomputed table must match the on-demand computation for \(phase.rawValue)")
        }
    }

    // MARK: - Representative tool placement

    func testTimelineToolsLiveInPhase2Only() {
        let create = OnboardingToolName.createTimelineCard.rawValue
        XCTAssertTrue(ToolBundlePolicy.allowedToolsForPhase(.phase2CareerStory).contains(create),
                      "create_timeline_card belongs to Phase 2")
        XCTAssertFalse(ToolBundlePolicy.allowedToolsForPhase(.phase1VoiceContext).contains(create),
                       "create_timeline_card must not be available in Phase 1")
    }

    func testIngestWritingSampleAvailableInPhase1() {
        XCTAssertTrue(
            ToolBundlePolicy.allowedToolsForPhase(.phase1VoiceContext)
                .contains(OnboardingToolName.ingestWritingSample.rawValue),
            "ingest_writing_sample is a Phase 1 (voice) tool")
    }

    // MARK: - Subphase inference

    func testInferSubphaseStartsAtWelcomeWithNoObjectives() {
        let sub = ToolBundlePolicy.inferSubphase(
            phase: .phase1VoiceContext, toolPaneCard: .none, objectives: [:])
        XCTAssertEqual(sub, .p1_welcome,
                       "with nothing complete and no UI card, Phase 1 starts at welcome")
        XCTAssertEqual(sub.phase, .phase1VoiceContext)
    }

    func testInferSubphaseUIStatePrecedence() {
        // An upload card forces the writing-samples subphase regardless of objectives.
        let sub = ToolBundlePolicy.inferSubphase(
            phase: .phase1VoiceContext, toolPaneCard: .uploadRequest, objectives: [:])
        XCTAssertEqual(sub, .p1_writingSamples,
                       "an active upload card takes precedence over objective inference")
    }

    func testInferSubphaseAdvancesPhase1ByObjectiveCompletion() {
        // Profile + writing samples done, job-search pending → job-search-context subphase.
        let objectives = [
            OnboardingObjectiveId.applicantProfileComplete.rawValue: "completed",
            OnboardingObjectiveId.writingSamplesCollected.rawValue: "completed",
            OnboardingObjectiveId.jobSearchContextCaptured.rawValue: "pending"
        ]
        let sub = ToolBundlePolicy.inferSubphase(
            phase: .phase1VoiceContext, toolPaneCard: .none, objectives: objectives)
        XCTAssertEqual(sub, .p1_jobSearchContext)
    }

    func testInferSubphaseAllPhase1ObjectivesCompleteReachesTransition() {
        let objectives = [
            OnboardingObjectiveId.applicantProfileComplete.rawValue: "completed",
            OnboardingObjectiveId.writingSamplesCollected.rawValue: "completed",
            OnboardingObjectiveId.jobSearchContextCaptured.rawValue: "completed"
        ]
        let sub = ToolBundlePolicy.inferSubphase(
            phase: .phase1VoiceContext, toolPaneCard: .none, objectives: objectives)
        XCTAssertEqual(sub, .p1_phaseTransition)
        XCTAssertTrue(ToolBundlePolicy.availableTools(in: sub)
            .contains(OnboardingToolName.nextPhase.rawValue),
            "next_phase must be reachable once Phase 1 objectives are complete")
    }

    func testCompletePhaseInfersCompletionSubphase() {
        let sub = ToolBundlePolicy.inferSubphase(
            phase: .complete, toolPaneCard: .none, objectives: [:])
        XCTAssertEqual(sub, .p4_completion)
    }

    // MARK: - Unavailability reason messaging

    func testUnavailabilityReasonNamesAvailableSubphasesWithinPhase() {
        // create_timeline_card is unavailable in p2_workPreferences but available in
        // other Phase 2 subphases — the reason should name where it becomes available.
        let reason = ToolBundlePolicy.unavailabilityReason(
            for: OnboardingToolName.createTimelineCard.rawValue,
            currentSubphase: .p2_workPreferences)
        XCTAssertTrue(reason.contains("p2_timeline_collection"),
                      "reason should point to a subphase where the tool is available; got: \(reason)")
    }

    func testUnavailabilityReasonForToolAbsentFromPhase() {
        // create_timeline_card never appears in any Phase 1 subphase.
        let reason = ToolBundlePolicy.unavailabilityReason(
            for: OnboardingToolName.createTimelineCard.rawValue,
            currentSubphase: .p1_welcome)
        XCTAssertTrue(reason.contains("not executable in the current interview stage"),
                      "a tool absent from the whole phase gets the generic stage message; got: \(reason)")
    }

    // MARK: - PhaseScript advance logic (default protocol implementations)

    func testPhaseScriptBlocksAdvanceUntilRequiredObjectivesComplete() {
        let script = PhaseOneScript()
        XCTAssertFalse(script.requiredObjectives.isEmpty)

        // Nothing complete → cannot advance, every required objective is missing.
        XCTAssertFalse(script.canAdvance(completedObjectives: []))
        XCTAssertEqual(Set(script.missingObjectives(completedObjectives: [])),
                       Set(script.requiredObjectives))

        // All complete → can advance, nothing missing.
        let all = Set(script.requiredObjectives)
        XCTAssertTrue(script.canAdvance(completedObjectives: all))
        XCTAssertTrue(script.missingObjectives(completedObjectives: all).isEmpty)
    }

    func testPhaseScriptPartialCompletionReportsExactGap() {
        let script = PhaseOneScript()
        let required = script.requiredObjectives
        guard required.count >= 2 else {
            return XCTFail("Phase 1 should require multiple objectives")
        }
        // Complete all but the last required objective.
        let completed = Set(required.dropLast())
        XCTAssertFalse(script.canAdvance(completedObjectives: completed))
        XCTAssertEqual(script.missingObjectives(completedObjectives: completed), [required.last!])
    }

    func testAllConcretePhaseScriptsHaveConsistentAdvanceLogic() {
        let scripts: [any PhaseScript] = [
            PhaseOneScript(), PhaseTwoScript(), PhaseThreeScript(), PhaseFourScript()
        ]
        for script in scripts {
            let required = Set(script.requiredObjectives)
            XCTAssertFalse(required.isEmpty, "\(script.phase.rawValue) declares required objectives")
            // canAdvance must be exactly "all required completed".
            XCTAssertTrue(script.canAdvance(completedObjectives: required),
                          "\(script.phase.rawValue) advances when all required objectives complete")
            XCTAssertFalse(script.canAdvance(completedObjectives: []),
                           "\(script.phase.rawValue) blocks advance with no objectives complete")
            // Extra unrelated completed objectives never block advance.
            XCTAssertTrue(script.canAdvance(completedObjectives: required.union(["unrelated_objective"])))
        }
    }
}
