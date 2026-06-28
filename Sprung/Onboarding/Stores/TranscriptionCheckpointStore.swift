//
//  TranscriptionCheckpointStore.swift
//  Sprung
//
//  Per-chunk checkpoint persistence for the PDF transcription stage.
//
//  A large PDF is transcribed in absolute page-range chunks (~50 pages each) that
//  are concatenated in memory. Before this store, ANY chunk throw discarded every
//  already-completed chunk — wpaf22 transcribed pages 1–59 of 190, then lost them
//  and persisted as if whole. This store checkpoints each successful chunk keyed by
//  its ABSOLUTE page range so an in-process retry resumes from the first missing
//  chunk instead of re-transcribing the whole document.
//
//  Chunk identity is the absolute `PDFChunk.pageRange` (NOT the document's page
//  count). `documentId` is fresh per `processDocument`, so resume survives an
//  in-process retry only — a fresh re-upload starts clean (cross-re-upload resume
//  is deliberately out of scope; orphans are swept by age).
//
//  Mirrors `ArtifactRecordStore`'s weak-ModelContext pattern: operations fail
//  gracefully (rather than crash) if the context is deallocated during teardown.
//

import Foundation
import Observation
import SwiftData

// MARK: - Model

/// One successfully-transcribed chunk, persisted so it survives a later-chunk
/// failure within the same in-process ingestion run.
@Model
final class TranscriptionChunkCheckpoint {
    /// Per-ingestion document identity (matches `processDocument`'s `documentId`).
    var documentId: String
    /// 1-based inclusive absolute page range — the chunk's identity.
    var lowerPage: Int
    var upperPage: Int
    /// JSON-encoded `TranscriptionPayload` for this chunk.
    var payloadJSON: String
    var createdAt: Date

    init(documentId: String, lowerPage: Int, upperPage: Int, payloadJSON: String, createdAt: Date = Date()) {
        self.documentId = documentId
        self.lowerPage = lowerPage
        self.upperPage = upperPage
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

// MARK: - Store

@Observable
@MainActor
final class TranscriptionCheckpointStore {
    /// Weak reference to ModelContext to prevent crashes during container teardown.
    /// Operations gracefully fail if the context is deallocated.
    private(set) weak var modelContext: ModelContext?

    init(context: ModelContext) {
        modelContext = context
        Logger.info("TranscriptionCheckpointStore initialized", category: .ai)
    }

    // MARK: - Context Management

    @discardableResult
    private func saveContext() -> Bool {
        guard let context = modelContext else {
            Logger.warning("ModelContext deallocated, skipping checkpoint save", category: .storage)
            return false
        }
        do {
            try context.save()
            return true
        } catch {
            Logger.error("SwiftData save failed: \(error.localizedDescription)", category: .storage)
            return false
        }
    }

    // MARK: - Codec

    /// `TranscriptionPayload` carries no Dates, so a plain codec is sufficient and
    /// avoids coupling this store to the IR's ISO-8601 provenance strategy.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Read

    /// All saved chunks for a document, decoded and sorted by ascending page range.
    /// Undecodable rows are skipped (logged) rather than aborting the resume.
    func savedChunks(documentId: String) -> [(pageRange: ClosedRange<Int>, payload: TranscriptionPayload)] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<TranscriptionChunkCheckpoint>(
            predicate: #Predicate { $0.documentId == documentId },
            sortBy: [SortDescriptor(\.lowerPage, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap { row in
            guard row.lowerPage <= row.upperPage,
                  let data = row.payloadJSON.data(using: .utf8),
                  let payload = try? Self.decoder.decode(TranscriptionPayload.self, from: data) else {
                Logger.warning(
                    "⚠️ Skipping undecodable transcription checkpoint (doc \(documentId), pages \(row.lowerPage)–\(row.upperPage))",
                    category: .ai
                )
                return nil
            }
            return (row.lowerPage...row.upperPage, payload)
        }
        .sorted { $0.pageRange.lowerBound < $1.pageRange.lowerBound }
    }

    // MARK: - Write

    /// Persist one successfully-transcribed chunk. A chunk with the same document
    /// id and page range overwrites the prior row (idempotent re-save on retry).
    func saveChunk(documentId: String, pageRange: ClosedRange<Int>, payload: TranscriptionPayload) {
        guard let modelContext else {
            Logger.warning("ModelContext deallocated, cannot save transcription checkpoint", category: .ai)
            return
        }
        let lower = pageRange.lowerBound
        let upper = pageRange.upperBound
        let json: String
        do {
            json = String(decoding: try Self.encoder.encode(payload), as: UTF8.self)
        } catch {
            Logger.error("Failed to encode transcription payload for checkpoint: \(error.localizedDescription)", category: .ai)
            ToastCenter.shared.show(.error("Couldn't checkpoint a transcription chunk — it will be re-transcribed if you resume. \(error.localizedDescription)"))
            return
        }

        // Overwrite any existing checkpoint for this exact chunk so a retry that
        // re-transcribes a chunk does not accumulate duplicate rows.
        let existingDescriptor = FetchDescriptor<TranscriptionChunkCheckpoint>(
            predicate: #Predicate { $0.documentId == documentId && $0.lowerPage == lower && $0.upperPage == upper }
        )
        for stale in (try? modelContext.fetch(existingDescriptor)) ?? [] {
            modelContext.delete(stale)
        }

        let checkpoint = TranscriptionChunkCheckpoint(
            documentId: documentId,
            lowerPage: lower,
            upperPage: upper,
            payloadJSON: json
        )
        modelContext.insert(checkpoint)
        saveContext()
    }

    // MARK: - Delete

    /// Drop every checkpoint for a document — called once a transcription completes
    /// whole, or when the user explicitly cancels the ingestion.
    func clear(documentId: String) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<TranscriptionChunkCheckpoint>(
            predicate: #Predicate { $0.documentId == documentId }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        guard !rows.isEmpty else { return }
        for row in rows { modelContext.delete(row) }
        saveContext()
        Logger.info("🧹 Cleared \(rows.count) transcription checkpoint(s) for document \(documentId)", category: .ai)
    }

    /// Age-based sweep of leftover checkpoints from runs that never completed (a
    /// crash, a hard abort, or an in-process retry that the user abandoned). Called
    /// at container startup so the store does not accumulate stale chunk JSON.
    func sweepOrphans(olderThanDays days: Int = 7) {
        guard let modelContext else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let descriptor = FetchDescriptor<TranscriptionChunkCheckpoint>(
            predicate: #Predicate { $0.createdAt < cutoff }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        guard !rows.isEmpty else { return }
        for row in rows { modelContext.delete(row) }
        saveContext()
        Logger.info("🧹 Swept \(rows.count) orphaned transcription checkpoint(s) older than \(days) days", category: .ai)
    }
}
