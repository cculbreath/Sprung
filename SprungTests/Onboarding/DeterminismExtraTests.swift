//
//  DeterminismExtraTests.swift
//  SprungTests
//
//  Additional determinism-seam coverage beyond DeterminismSeamTests. These scenarios
//  are NOT duplicated there:
//
//   • The four whitelist members the original test omits (update/delete section &
//     publication cards) and full parity between the gateway's re-execute predicate
//     and the canonical OnboardingToolName.replayReExecutableTools set.
//   • A multi-card mint sequence driven through a REAL actor service
//     (SectionCardManagementService) records its ids in order, then replay reproduces
//     them across the actor hop — proving the seam at the service boundary, not just
//     the bare provider.
//   • Replay exhaustion MID-sequence: ids past the recorded count diverge (and flag),
//     but ids still within the recorded count keep being served exactly — the run
//     completes rather than aborting.
//

import XCTest
import SwiftyJSON
@testable import Sprung

final class DeterminismExtraTests: XCTestCase {

    // MARK: - Whitelist completeness (new members + parity)

    /// The update/delete variants for section & publication cards are re-executable
    /// too — they are pure, args-derived local mutations. DeterminismSeamTests only
    /// asserts the create/* members, so cover the remaining four here.
    func testUpdateDeleteCardVariantsAreReExecutable() {
        for tool in [OnboardingToolName.updateSectionCard, .deleteSectionCard,
                     .updatePublicationCard, .deletePublicationCard] {
            XCTAssertTrue(ReplayToolGateway.shouldReExecute(toolName: tool.rawValue),
                          "\(tool.rawValue) is a pure local mutation and must be re-executed")
        }
    }

    /// The gateway predicate must agree EXACTLY with the canonical whitelist set —
    /// no tool re-executes that the constant does not list, and vice versa. This is
    /// the regression guard if someone edits one source but not the other.
    func testGatewayPredicateMatchesCanonicalWhitelist() {
        for name in OnboardingToolName.allCases {
            let expected = OnboardingToolName.replayReExecutableTools.contains(name.rawValue)
            XCTAssertEqual(ReplayToolGateway.shouldReExecute(toolName: name.rawValue), expected,
                           "re-execute classification for \(name.rawValue) diverges from the canonical set")
        }
    }

    // MARK: - Multi-card mint through a real actor service, then replay

    /// Drive three card creations through the actual SectionCardManagementService actor
    /// under a recording scope; the ids land in `mintedIds` in creation order. Replaying
    /// that sequence through a fresh service run reproduces the identical ids — the
    /// seam survives the `await actor.method()` hop because task-locals propagate to it.
    func testMultiCardMintSequenceReplaysIdenticallyAcrossActorHop() async {
        let recording = DeterminismContext(mode: .recording)
        let recordedIds: [String] = await DeterminismScope.$current.withValue(recording) {
            let service = SectionCardManagementService(eventBus: EventCoordinator())
            let r1 = await service.createSectionCard(sectionType: "award", fields: JSON(["title": "A"]))
            let r2 = await service.createSectionCard(sectionType: "language", fields: JSON(["language": "Welsh"]))
            let r3 = await service.createPublicationCard(fields: JSON(["name": "P"]))
            return [r1["id"].stringValue, r2["id"].stringValue, r3["id"].stringValue]
        }
        XCTAssertEqual(recordedIds.count, 3)
        XCTAssertEqual(Set(recordedIds).count, 3, "each created card gets a distinct id")
        XCTAssertEqual(recording.mintedIds, recordedIds,
                       "the actor's mints were captured, in order, by the bound scope")

        let replaying = DeterminismContext(mode: .replaying(recording.mintedIds))
        let replayedIds: [String] = await DeterminismScope.$current.withValue(replaying) {
            let service = SectionCardManagementService(eventBus: EventCoordinator())
            let r1 = await service.createSectionCard(sectionType: "award", fields: JSON(["title": "A"]))
            let r2 = await service.createSectionCard(sectionType: "language", fields: JSON(["language": "Welsh"]))
            let r3 = await service.createPublicationCard(fields: JSON(["name": "P"]))
            return [r1["id"].stringValue, r2["id"].stringValue, r3["id"].stringValue]
        }
        XCTAssertEqual(replayedIds, recordedIds, "replay re-execution reproduces the recorded card ids")
        XCTAssertFalse(replaying.didExhaust)
    }

    // MARK: - Mid-sequence exhaustion still completes the run

    /// A replay seeded with FEWER ids than the run will request: the in-range mints are
    /// served exactly, the first out-of-range mint diverges (a fresh UUID) and flags
    /// exhaustion, and subsequent mints keep working — execution proceeds to the end
    /// rather than aborting. (DeterminismSeamTests only proves the single-overflow case.)
    func testReplayExhaustionMidSequenceServesPrefixThenDiverges() {
        let ctx = DeterminismContext(mode: .replaying(["card-1", "card-2"]))

        // First two are served verbatim from the recording.
        XCTAssertEqual(ctx.nextUUID(), "card-1")
        XCTAssertEqual(ctx.nextUUID(), "card-2")
        XCTAssertFalse(ctx.didExhaust, "consuming exactly the recorded prefix must not flag exhaustion")

        // Third request overruns the recording — diverges with a fresh, valid id.
        let overflow1 = ctx.nextUUID()
        XCTAssertTrue(ctx.didExhaust, "the first over-count request must flag exhaustion")
        XCTAssertNotEqual(overflow1, "card-1")
        XCTAssertNotEqual(overflow1, "card-2")
        XCTAssertNotNil(UUID(uuidString: overflow1), "an exhausted mint is still a usable UUID")

        // A fourth request still succeeds (run completes; the flag stays latched).
        let overflow2 = ctx.nextUUID()
        XCTAssertNotEqual(overflow1, overflow2, "post-exhaustion mints remain distinct")
        XCTAssertTrue(ctx.didExhaust)
    }

    /// The recording scope itself is unbounded: it mints and remembers any number of
    /// ids in order, distinct, never exhausting. (Complements the 3-id case in the
    /// base suite with a larger sequence.)
    func testRecordingScopeMintsUnboundedDistinctSequence() {
        let ctx = DeterminismContext(mode: .recording)
        let ids = (0..<25).map { _ in ctx.nextUUID() }
        XCTAssertEqual(ids, ctx.mintedIds, "recording remembers every mint in order")
        XCTAssertEqual(Set(ids).count, ids.count, "all minted ids are distinct")
        XCTAssertFalse(ctx.didExhaust, "a recording scope never exhausts")
    }
}
