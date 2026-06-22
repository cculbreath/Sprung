//
//  TranscriptionCheckpointStoreTests.swift
//  SprungTests
//
//  Persistence + ordering contract for the per-chunk PDF transcription checkpoint
//  store. A large PDF transcribes in absolute page-range chunks; this store lets a
//  later-chunk failure resume from the first missing chunk instead of re-reading
//  the whole document. The load-bearing guarantees exercised here:
//    • a chunk round-trips by its absolute page range
//    • savedChunks returns ascending-by-lowerPage regardless of insertion order
//      (the merge concatenates fullText in that order)
//    • re-saving the same range overwrites (idempotent retry, no duplicate rows)
//    • clear / sweepOrphans drop rows
//    • an undecodable row is skipped, not fatal
//
//  No LLMFacade is touched — the store is pure persistence over `TranscriptionPayload`.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class TranscriptionCheckpointStoreTests: InMemoryStoreCase {

    // MARK: - Fixtures

    /// Minimal, distinguishable payload — `fullText` carries the marker we assert on.
    private func makePayload(marker: String) -> TranscriptionPayload {
        TranscriptionPayload(
            fullText: marker,
            visualElements: [],
            tables: [],
            productionQuality: TranscriptionProductionQuality(typesettingSystemGuess: "LaTeX"),
            structure: "",
            docMeta: DocMeta(pageCount: 190, language: "en", docClassGuess: "paper")
        )
    }

    // MARK: - Round-trip + ordering

    func testSavedChunksRoundTripAndOrderAscending() throws {
        let store = TranscriptionCheckpointStore(context: context)
        let doc = "doc-A"

        // Insert OUT of order: 60–118 before 1–59.
        store.saveChunk(documentId: doc, pageRange: 60...118, payload: makePayload(marker: "chunk-2"))
        store.saveChunk(documentId: doc, pageRange: 1...59, payload: makePayload(marker: "chunk-1"))

        let saved = store.savedChunks(documentId: doc)
        XCTAssertEqual(saved.count, 2)
        // Sorted ascending by lowerPage — this is the order the merge concatenates.
        XCTAssertEqual(saved.map(\.pageRange), [1...59, 60...118])
        XCTAssertEqual(saved.map(\.payload.fullText), ["chunk-1", "chunk-2"])
    }

    func testSavedChunksIsolatedByDocumentId() throws {
        let store = TranscriptionCheckpointStore(context: context)
        store.saveChunk(documentId: "doc-A", pageRange: 1...50, payload: makePayload(marker: "A"))
        store.saveChunk(documentId: "doc-B", pageRange: 1...50, payload: makePayload(marker: "B"))

        XCTAssertEqual(store.savedChunks(documentId: "doc-A").map(\.payload.fullText), ["A"])
        XCTAssertEqual(store.savedChunks(documentId: "doc-B").map(\.payload.fullText), ["B"])
    }

    func testEmptyWhenNoChunksSaved() throws {
        let store = TranscriptionCheckpointStore(context: context)
        XCTAssertTrue(store.savedChunks(documentId: "never-saved").isEmpty)
    }

    // MARK: - Idempotent re-save (retry overwrites, no duplicates)

    func testResaveSameRangeOverwritesInPlace() throws {
        let store = TranscriptionCheckpointStore(context: context)
        let doc = "doc-A"
        store.saveChunk(documentId: doc, pageRange: 1...59, payload: makePayload(marker: "first"))
        store.saveChunk(documentId: doc, pageRange: 1...59, payload: makePayload(marker: "second"))

        let saved = store.savedChunks(documentId: doc)
        XCTAssertEqual(saved.count, 1, "Re-saving the same page range must overwrite, not duplicate")
        XCTAssertEqual(saved.first?.payload.fullText, "second")
        // One physical row.
        XCTAssertEqual(try fetchAll(TranscriptionChunkCheckpoint.self).count, 1)
    }

    // MARK: - clear

    func testClearRemovesOnlyTargetDocument() throws {
        let store = TranscriptionCheckpointStore(context: context)
        store.saveChunk(documentId: "doc-A", pageRange: 1...59, payload: makePayload(marker: "A1"))
        store.saveChunk(documentId: "doc-A", pageRange: 60...118, payload: makePayload(marker: "A2"))
        store.saveChunk(documentId: "doc-B", pageRange: 1...59, payload: makePayload(marker: "B1"))

        store.clear(documentId: "doc-A")

        XCTAssertTrue(store.savedChunks(documentId: "doc-A").isEmpty)
        XCTAssertEqual(store.savedChunks(documentId: "doc-B").map(\.payload.fullText), ["B1"])
    }

    // MARK: - sweepOrphans

    func testSweepOrphansDropsOnlyStaleRows() throws {
        let store = TranscriptionCheckpointStore(context: context)

        // Fresh row (kept) via the store.
        store.saveChunk(documentId: "fresh", pageRange: 1...50, payload: makePayload(marker: "fresh"))

        // Stale row (createdAt 30 days ago) inserted directly so we control the date.
        let stale = TranscriptionChunkCheckpoint(
            documentId: "stale",
            lowerPage: 1,
            upperPage: 50,
            payloadJSON: "{}",
            createdAt: Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        )
        insert(stale)
        saveContext()

        store.sweepOrphans(olderThanDays: 7)

        XCTAssertEqual(store.savedChunks(documentId: "fresh").count, 1, "Recent checkpoint must survive the sweep")
        // The stale row is gone (it never decodes anyway, but it should be physically deleted).
        let remaining = try fetchAll(TranscriptionChunkCheckpoint.self)
        XCTAssertEqual(remaining.map(\.documentId), ["fresh"])
    }

    // MARK: - Resilience

    func testUndecodableRowIsSkippedNotFatal() throws {
        let store = TranscriptionCheckpointStore(context: context)
        let doc = "doc-A"

        // A good row plus a hand-corrupted row for the same document.
        store.saveChunk(documentId: doc, pageRange: 1...59, payload: makePayload(marker: "good"))
        insert(TranscriptionChunkCheckpoint(documentId: doc, lowerPage: 60, upperPage: 118, payloadJSON: "not json"))
        saveContext()

        let saved = store.savedChunks(documentId: doc)
        XCTAssertEqual(saved.count, 1, "Undecodable row is skipped; the valid chunk still resumes")
        XCTAssertEqual(saved.first?.payload.fullText, "good")
    }
}
