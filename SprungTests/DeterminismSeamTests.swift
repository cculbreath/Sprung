//
//  DeterminismSeamTests.swift
//  SprungTests
//
//  Validates the id seam that makes onboarding replay re-execution deterministic:
//  recording captures minted ids in order, replay serves them back, exhaustion is
//  flagged, the seam propagates across the task-local boundary an actor hop crosses,
//  the tape field round-trips (and old tapes decode), and the re-execution whitelist
//  is correct. The "byte-identical re-execution" property is proven at the seam
//  level: a recorded mint sequence, replayed, reproduces the same ids.
//

import XCTest
@testable import Sprung

final class DeterminismSeamTests: XCTestCase {

    // MARK: - Recording / replaying scopes

    func testRecordingScopeCapturesMintsInOrder() {
        let ctx = DeterminismContext(mode: .recording)
        let a = ctx.nextUUID()
        let b = ctx.nextUUID()
        let c = ctx.nextUUID()
        XCTAssertEqual([a, b, c], ctx.mintedIds, "recording must capture mints in order")
        XCTAssertEqual(Set([a, b, c]).count, 3, "minted ids must be distinct")
        XCTAssertFalse(ctx.didExhaust)
    }

    func testReplayingScopeServesRecordedSequence() {
        let recorded = ["id-A", "id-B", "id-C"]
        let ctx = DeterminismContext(mode: .replaying(recorded))
        XCTAssertEqual(ctx.nextUUID(), "id-A")
        XCTAssertEqual(ctx.nextUUID(), "id-B")
        XCTAssertEqual(ctx.nextUUID(), "id-C")
        XCTAssertFalse(ctx.didExhaust, "serving exactly the recorded count must not exhaust")
        XCTAssertTrue(ctx.mintedIds.isEmpty, "a replay scope mints nothing of its own")
    }

    func testReplayExhaustionIsFlaggedAndStillProduces() {
        let ctx = DeterminismContext(mode: .replaying(["only-one"]))
        XCTAssertEqual(ctx.nextUUID(), "only-one")
        let overflow = ctx.nextUUID()   // one more than recorded → divergence
        XCTAssertTrue(ctx.didExhaust, "asking for more ids than recorded must flag exhaustion")
        XCTAssertFalse(overflow.isEmpty, "exhaustion still returns a usable id so execution proceeds")
        XCTAssertNotEqual(overflow, "only-one")
    }

    // MARK: - Provider + task-local plumbing

    func testProviderWithoutScopeMintsPlainUUID() {
        XCTAssertNil(DeterminismScope.current, "no scope should be bound by default")
        let a = DeterminismIDProvider.nextUUID()
        let b = DeterminismIDProvider.nextUUID()
        XCTAssertNotEqual(a, b)
        XCTAssertNotNil(UUID(uuidString: a), "plain path must yield a valid UUID string")
    }

    func testProviderRoutesThroughBoundScope() {
        let ctx = DeterminismContext(mode: .replaying(["seam-1", "seam-2"]))
        DeterminismScope.$current.withValue(ctx) {
            XCTAssertEqual(DeterminismIDProvider.nextUUID(), "seam-1")
            XCTAssertEqual(DeterminismIDProvider.nextUUID(), "seam-2")
        }
        // Binding is dynamically scoped — gone after withValue returns.
        XCTAssertNil(DeterminismScope.current)
    }

    /// The load-bearing property: the seam set in the executor's task is visible to
    /// a mint that happens INSIDE an actor the tool awaits (timeline/section card
    /// services are actors). Task-local values propagate across `await actor.method()`
    /// because that runs on the same task.
    func testSeamPropagatesAcrossActorHop() async {
        actor MintingService {
            func mint() -> String { DeterminismIDProvider.nextUUID() }
        }
        let service = MintingService()
        let ctx = DeterminismContext(mode: .replaying(["actor-id-1", "actor-id-2"]))
        let ids = await DeterminismScope.$current.withValue(ctx) {
            async let first = service.mint()
            async let second = service.mint()
            return await [first, second]
        }
        // Both mints (each on the actor's executor) drew from the bound seam.
        XCTAssertEqual(Set(ids), Set(["actor-id-1", "actor-id-2"]))
    }

    // MARK: - Record → replay reproduces the same ids (re-execution faithfulness)

    /// Simulates a tool's pure id-minting under recording, then re-execution under
    /// replay: replaying the captured sequence reproduces the identical ids, which
    /// is exactly why a re-executed "create" keeps the id that a later recorded
    /// "update" references.
    func testRecordThenReplayReproducesSameIds() {
        // Record pass.
        let recording = DeterminismContext(mode: .recording)
        let recordedIds = DeterminismScope.$current.withValue(recording) {
            [DeterminismIDProvider.nextUUID(), DeterminismIDProvider.nextUUID()]
        }
        // Replay pass seeded with what recording captured.
        let replaying = DeterminismContext(mode: .replaying(recording.mintedIds))
        let replayedIds = DeterminismScope.$current.withValue(replaying) {
            [DeterminismIDProvider.nextUUID(), DeterminismIDProvider.nextUUID()]
        }
        XCTAssertEqual(recordedIds, replayedIds, "replay must reproduce the recorded id sequence exactly")
        XCTAssertFalse(replaying.didExhaust)
    }

    // MARK: - Tape field Codable

    func testTapeToolResultMintedIdsRoundTrip() throws {
        let original = TapeToolResult(turnIndex: 3, callId: "toolu_9", name: "create_timeline_card",
                                      argumentsJSON: nil, output: #"{"id":"x"}"#, status: "completed",
                                      mintedIds: ["x"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapeToolResult.self, from: data)
        XCTAssertEqual(decoded.mintedIds, ["x"])
    }

    /// Pre-seam (v1) tapes have no `mintedIds` key — they must still decode (nil).
    func testLegacyTapeToolResultDecodesWithoutMintedIds() throws {
        let legacyJSON = #"""
        {"turnIndex":0,"callId":"toolu_1","name":"glob","output":"a.swift","status":"completed"}
        """#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TapeToolResult.self, from: data)
        XCTAssertNil(decoded.mintedIds, "missing mintedIds key must decode to nil, not throw")
        XCTAssertEqual(decoded.callId, "toolu_1")
    }

    // MARK: - Re-execution whitelist

    func testShouldReExecuteWhitelist() {
        // Pure-local state mutators are re-executed to rebuild domain state.
        for tool in [OnboardingToolName.createTimelineCard, .updateTimelineCard, .deleteTimelineCard,
                     .reorderTimelineCards, .createSectionCard, .createPublicationCard,
                     .createWebArtifact, .ingestWritingSample, .updateDossierNotes, .updateTodoList] {
            XCTAssertTrue(ReplayToolGateway.shouldReExecute(toolName: tool.rawValue),
                          "\(tool.rawValue) should be re-executed during replay")
        }
        // External / IO / LLM / user-prompt tools stay served verbatim.
        for tool in [OnboardingToolName.readFile, .grepSearch, .getUserOption,
                     .getApplicantProfile, .listArtifacts] {
            XCTAssertFalse(ReplayToolGateway.shouldReExecute(toolName: tool.rawValue),
                           "\(tool.rawValue) must NOT be re-executed during replay")
        }
        // extract_document rebuilds its artifact via output-inspect, not re-exec.
        XCTAssertFalse(ReplayToolGateway.shouldReExecute(toolName: "extract_document"))
        // Unknown tool names are never re-executed.
        XCTAssertFalse(ReplayToolGateway.shouldReExecute(toolName: "nonexistent_tool"))
    }

    // MARK: - Seam completeness lint

    /// Regression guard: every id minted by a re-executable tool MUST route through
    /// `DeterminismIDProvider`, or replay re-execution would mint a fresh id and the
    /// later "update/delete X" turn would miss. A raw `UUID()` reintroduced into a
    /// seam file silently breaks that — this fails the build instead. Anchored to
    /// `#filePath` so it reads the real sources; skips if the build was relocated.
    func testSeamFilesHaveNoRawUUIDConstructor() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SprungTests/
            .deletingLastPathComponent()   // repo root
        let seamFiles = [
            "Sprung/Onboarding/Services/TimelineManagementService.swift",
            "Sprung/Onboarding/Services/SectionCardManagementService.swift",
            "Sprung/Onboarding/Tools/Implementations/CreateWebArtifactTool.swift",
            "Sprung/Onboarding/Tools/Implementations/IngestWritingSampleTool.swift",
        ]
        for relative in seamFiles {
            let url = repoRoot.appendingPathComponent(relative)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("seam source not readable at \(url.path) — skipping lint (relocated build)")
            }
            // Count raw `UUID()` constructors, excluding the seam's own `nextUUID()`.
            let rawCount = source.components(separatedBy: "UUID()").count - 1
            let seamCount = source.components(separatedBy: "nextUUID()").count - 1
            XCTAssertEqual(rawCount - seamCount, 0,
                "\(relative) contains a raw UUID() constructor — route it through DeterminismIDProvider.nextUUID() so replay re-execution stays deterministic")
        }
    }
}
