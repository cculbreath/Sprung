//
//  TranscriptionLogTests.swift
//  SprungTests
//
//  The per-chunk transcription log on a PDF IR is the AUTHORITATIVE completeness
//  record: resume/reuse decisions read it directly (never a transcript heuristic).
//  These tests pin that contract — completeness, payload-carrying round-trip,
//  exclusion from the cache-stable rendering, and backward-compatible decode of
//  IRs written before the log existed.
//

import XCTest
import Foundation
@testable import Sprung

final class TranscriptionLogTests: XCTestCase {

    private static let provenance = IRProvenance(
        sourceArtifactId: "artifact-1",
        modelId: "model-x",
        promptVersion: "v1",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    private func payload(_ text: String) -> TranscriptionPayload {
        TranscriptionPayload(
            fullText: text,
            visualElements: [],
            tables: [],
            productionQuality: TranscriptionProductionQuality(typesettingSystemGuess: "LaTeX"),
            structure: "",
            docMeta: DocMeta(pageCount: 1)
        )
    }

    private func transcription(log: [TranscribedChunk], mergedText: String = "merged") -> DocumentTranscription {
        DocumentTranscription(
            fullText: mergedText,
            productionQuality: TranscriptionProductionQuality(typesettingSystemGuess: "LaTeX"),
            docMeta: DocMeta(pageCount: 40),
            provenance: Self.provenance,
            transcriptionLog: log
        )
    }

    // MARK: - Completeness

    func testAllCompletedChunksIsComplete() {
        let t = transcription(log: [
            TranscribedChunk(pageRange: 1...20, status: .completed, payload: payload("a")),
            TranscribedChunk(pageRange: 21...40, status: .completed, payload: payload("b"))
        ])
        XCTAssertTrue(t.isComplete)
        XCTAssertEqual(t.missingPagesDescription, "")
    }

    func testAnyFailedChunkIsIncompleteAndNamesMissingPages() {
        let t = transcription(log: [
            TranscribedChunk(pageRange: 1...20, status: .completed, payload: payload("a")),
            TranscribedChunk(pageRange: 21...40, status: .failed, payload: nil, failureReason: "timeout")
        ])
        XCTAssertFalse(t.isComplete)
        XCTAssertEqual(t.missingPagesDescription, "21–40")
    }

    func testEmptyLogIsNeverComplete() {
        // A pre-log IR (or a non-chunked source) carries no log. We must NOT assume
        // completeness we did not record — re-transcribe rather than reuse blindly.
        XCTAssertFalse(transcription(log: []).isComplete)
    }

    // MARK: - Round-trip (payloads must survive for resume)

    func testLogWithPayloadsSurvivesJSONRoundTrip() throws {
        let original = IntermediateRepresentation.pdf(transcription(log: [
            TranscribedChunk(pageRange: 1...20, status: .completed, payload: payload("chunk-1-text")),
            TranscribedChunk(pageRange: 21...40, status: .failed, payload: nil, failureReason: "429")
        ]))

        let restored = IntermediateRepresentation.decode(fromJSONString: try original.encodedJSONString())
        guard case .pdf(let t)? = restored else { return XCTFail("expected .pdf IR") }

        XCTAssertEqual(t.transcriptionLog.count, 2)
        XCTAssertEqual(t.transcriptionLog[0].status, .completed)
        XCTAssertEqual(t.transcriptionLog[0].payload?.fullText, "chunk-1-text")
        XCTAssertEqual(t.transcriptionLog[1].status, .failed)
        XCTAssertNil(t.transcriptionLog[1].payload)
        XCTAssertEqual(t.transcriptionLog[1].failureReason, "429")
        XCTAssertFalse(t.isComplete)
    }

    // MARK: - Cache invariant (log must NOT leak into the rendered source block)

    func testRenderingExcludesTranscriptionLog() {
        // A sentinel that lives ONLY in a log payload, never in the merged fullText.
        let t = transcription(
            log: [TranscribedChunk(pageRange: 1...20, status: .completed, payload: payload("LOG-ONLY-SENTINEL"))],
            mergedText: "the merged extraction text"
        )
        let rendered = IntermediateRepresentation.pdf(t).renderedForExtraction()
        XCTAssertFalse(rendered.contains("LOG-ONLY-SENTINEL"),
                       "transcriptionLog must not appear in renderedForExtraction (prompt-cache byte invariant)")
        XCTAssertTrue(rendered.contains("the merged extraction text"))
    }

    // MARK: - Backward compatibility (IRs written before the log existed)

    func testDecodeOfPreLogIRDefaultsToEmptyLog() throws {
        // Encode a current IR, then strip the transcriptionLog key to simulate a
        // record persisted before the field existed; it must still decode (log = []).
        let encoded = try IntermediateRepresentation.pdf(transcription(log: [
            TranscribedChunk(pageRange: 1...40, status: .completed, payload: payload("x"))
        ])).encodedJSONString()

        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
        )
        var pdf = try XCTUnwrap(root["pdf"] as? [String: Any])
        pdf.removeValue(forKey: "transcriptionLog")
        root["pdf"] = pdf
        let stripped = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)

        let restored = IntermediateRepresentation.decode(fromJSONString: stripped)
        guard case .pdf(let t)? = restored else { return XCTFail("pre-log IR should still decode") }
        XCTAssertEqual(t.transcriptionLog.count, 0)
        XCTAssertFalse(t.isComplete)
    }
}
