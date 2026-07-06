//
//  BackgroundActivityTrackerTests.swift
//  SprungTests
//
//  Pure-logic coverage for BackgroundActivityTracker: operation lifecycle
//  transitions, the derived running-operation accessors driving the
//  main-window indicator, selection behavior, and the operation-type
//  display metadata (distinct icons per type).
//

import XCTest
@testable import Sprung

@MainActor
final class BackgroundActivityTrackerTests: XCTestCase {

    // MARK: - Lifecycle

    func testTrackOperationStartsRunningAndInsertsNewestFirst() {
        let tracker = BackgroundActivityTracker()
        tracker.trackOperation(id: "first", type: .preprocessing, name: "First")
        tracker.trackOperation(id: "second", type: .eventDiscovery, name: "Second")

        XCTAssertEqual(tracker.operations.map(\.id), ["second", "first"])
        XCTAssertEqual(tracker.operations.map(\.status), [.running, .running])
        XCTAssertNil(tracker.getOperation(id: "second")?.endTime)
    }

    func testRunningAccessorsReflectLifecycleTransitions() {
        let tracker = BackgroundActivityTracker()
        XCTAssertEqual(tracker.runningCount, 0)
        XCTAssertFalse(tracker.hasRunningOperations)
        XCTAssertTrue(tracker.runningOperations.isEmpty)

        tracker.trackOperation(id: "a", type: .leadEnrichment, name: "Lead A")
        tracker.trackOperation(id: "b", type: .eventDiscovery, name: "Events B")
        XCTAssertEqual(tracker.runningCount, 2)
        XCTAssertTrue(tracker.hasRunningOperations)
        // Newest first, matching `operations` ordering.
        XCTAssertEqual(tracker.runningOperations.map(\.name), ["Events B", "Lead A"])

        tracker.markCompleted(operationId: "b")
        XCTAssertEqual(tracker.runningCount, 1)
        XCTAssertEqual(tracker.runningOperations.map(\.id), ["a"])

        tracker.markFailed(operationId: "a", error: "boom")
        XCTAssertEqual(tracker.runningCount, 0)
        XCTAssertFalse(tracker.hasRunningOperations)
        // Finished operations stay in `operations` until clearCompleted().
        XCTAssertEqual(tracker.operations.count, 2)
    }

    func testMarkCompletedSetsEndTimeAndClearsPhase() {
        let tracker = BackgroundActivityTracker()
        tracker.trackOperation(id: "op", type: .eventDiscovery, name: "Run")
        tracker.updatePhase(operationId: "op", phase: "Searching: swift meetups")

        tracker.markCompleted(operationId: "op")
        let operation = tracker.getOperation(id: "op")
        XCTAssertEqual(operation?.status, .completed)
        XCTAssertNotNil(operation?.endTime)
        XCTAssertNil(operation?.currentPhase)
        XCTAssertNil(operation?.error)
    }

    func testMarkFailedRecordsErrorAndAppendsErrorTranscriptEntry() {
        let tracker = BackgroundActivityTracker()
        tracker.trackOperation(id: "op", type: .leadEnrichment, name: "Lead")

        tracker.markFailed(operationId: "op", error: "fetch failed")
        let operation = tracker.getOperation(id: "op")
        XCTAssertEqual(operation?.status, .failed)
        XCTAssertEqual(operation?.error, "fetch failed")
        XCTAssertNotNil(operation?.endTime)
        XCTAssertNil(operation?.currentPhase)
        XCTAssertEqual(operation?.transcript.last?.entryType, .error)
        XCTAssertEqual(operation?.transcript.last?.content, "fetch failed")
    }

    func testUpdatePhaseSetsCurrentPhaseAndAppendsPhaseEntry() {
        let tracker = BackgroundActivityTracker()
        tracker.trackOperation(id: "op", type: .eventDiscovery, name: "Run")

        tracker.updatePhase(operationId: "op", phase: "Fetching: example.com")
        let operation = tracker.getOperation(id: "op")
        XCTAssertEqual(operation?.currentPhase, "Fetching: example.com")
        XCTAssertEqual(operation?.transcript.count, 1)
        XCTAssertEqual(operation?.transcript.last?.entryType, .phase)
        XCTAssertEqual(operation?.transcript.last?.content, "Fetching: example.com")
    }

    func testMutationsOnUnknownOperationIdAreNoOps() {
        let tracker = BackgroundActivityTracker()
        tracker.trackOperation(id: "op", type: .preprocessing, name: "Job")

        tracker.updatePhase(operationId: "missing", phase: "x")
        tracker.appendTranscript(operationId: "missing", entryType: .system, content: "x")
        tracker.markCompleted(operationId: "missing")
        tracker.markFailed(operationId: "missing", error: "x")
        tracker.addTokenUsage(operationId: "missing", input: 1, output: 1)

        let operation = tracker.getOperation(id: "op")
        XCTAssertEqual(operation?.status, .running)
        XCTAssertTrue(operation?.transcript.isEmpty ?? false)
        XCTAssertEqual(tracker.operations.count, 1)
    }

    // MARK: - Selection

    func testSelectionAutoSelectsOnlyRunningOperation() {
        let tracker = BackgroundActivityTracker()
        tracker.trackOperation(id: "a", type: .preprocessing, name: "A")
        XCTAssertEqual(tracker.selectedOperationId, "a")

        // Two running operations: selection sticks with the first.
        tracker.trackOperation(id: "b", type: .eventDiscovery, name: "B")
        XCTAssertEqual(tracker.selectedOperationId, "a")

        // Real contract: once the earlier operations have finished, a newly
        // tracked operation is the sole running one and steals selection.
        tracker.markCompleted(operationId: "a")
        tracker.markCompleted(operationId: "b")
        tracker.trackOperation(id: "c", type: .leadEnrichment, name: "C")
        XCTAssertEqual(tracker.selectedOperationId, "c")
    }

    func testClearCompletedRemovesFinishedOperationsAndRepairsSelection() {
        let tracker = BackgroundActivityTracker()
        tracker.trackOperation(id: "done", type: .preprocessing, name: "Done")
        tracker.trackOperation(id: "failed", type: .leadEnrichment, name: "Failed")
        tracker.trackOperation(id: "live", type: .eventDiscovery, name: "Live")
        tracker.markCompleted(operationId: "done")
        tracker.markFailed(operationId: "failed", error: "boom")
        tracker.selectedOperationId = "done"

        tracker.clearCompleted()
        XCTAssertEqual(tracker.operations.map(\.id), ["live"])
        XCTAssertEqual(tracker.selectedOperationId, "live")
        XCTAssertEqual(tracker.runningCount, 1)
    }

    // MARK: - Operation-Type Metadata

    func testOperationTypesHaveDistinctIconsAndDisplayNames() {
        let types = BackgroundOperationType.allCases
        XCTAssertEqual(Set(types.map(\.icon)).count, types.count, "each type needs a distinct SF Symbol")
        XCTAssertEqual(Set(types.map(\.displayName)).count, types.count)
        for type in types {
            XCTAssertFalse(type.displayName.isEmpty)
            XCTAssertFalse(type.icon.isEmpty)
        }
        XCTAssertEqual(BackgroundOperationType.eventDiscovery.displayName, "Event Discovery")
        XCTAssertEqual(BackgroundOperationType.leadEnrichment.displayName, "Lead Enrichment")
    }
}
