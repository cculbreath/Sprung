//
//  BudgetFailedExtractionRegistry.swift
//  Sprung
//
//  Session-scoped record of document-extraction passes that failed because the
//  API balance was exhausted. Populated as extraction fails fast (current
//  behavior, no suspend), drained on resume so the failed passes are re-run
//  against the artifact's stored intermediate representation — protecting
//  knowledge-card quality from a silent budget outage.
//
//  In-memory by design: resume happens within the same app run, so no SwiftData
//  migration is needed.
//

import Foundation

/// Records which extraction passes failed on budget, keyed by artifact filename
/// (the SwiftData `ArtifactRecord` mints its own id distinct from the in-flight
/// JSON record, so filename is the reliable join key at resume time).
@MainActor
final class BudgetFailedExtractionRegistry {

    /// One artifact's outstanding budget-failed passes.
    struct Entry {
        let filename: String
        var passes: AnthropicDocumentAnalysisService.PassSelection
    }

    private var entries: [String: Entry] = [:]

    /// Record (OR-merging) the passes that failed for a filename.
    func record(filename: String, passes: AnthropicDocumentAnalysisService.PassSelection) {
        if var existing = entries[filename] {
            existing.passes = existing.passes.merged(with: passes)
            entries[filename] = existing
        } else {
            entries[filename] = Entry(filename: filename, passes: passes)
        }
        Logger.info("💳 Recorded budget-failed extraction passes for \(filename)", category: .ai)
    }

    /// Return and clear all recorded entries.
    func drain() -> [Entry] {
        let drained = Array(entries.values)
        entries.removeAll()
        return drained
    }

    /// Clear without re-running (session reset).
    func reset() {
        entries.removeAll()
    }

    /// Map a single extraction-pass failure label to the pass it represents.
    /// Labels are emitted by `AnthropicDocumentAnalysisService.runPasses` as
    /// `"summary — <file>: …"`, `"skill extraction — <file>: …"`, and
    /// `"narrative cards — <file>: …"`. Narrative-card failures also re-select
    /// enrichment (it runs off verified cards). Returns nil for unrecognized labels.
    nonisolated static func passSelection(forFailureLabel label: String) -> AnthropicDocumentAnalysisService.PassSelection? {
        let head = label.lowercased()
        if head.hasPrefix("summary") {
            return .init(summary: true, skills: false, narrativeCards: false, enrichment: false)
        }
        if head.hasPrefix("skill") {
            return .init(summary: false, skills: true, narrativeCards: false, enrichment: false)
        }
        if head.hasPrefix("narrative") {
            return .init(summary: false, skills: false, narrativeCards: true, enrichment: true)
        }
        // Whole-document failure (e.g. transcription stage threw, or a total
        // analysis failure recorded by DocumentProcessingService.runAnalysis) —
        // re-run EVERY pass on budget top-up.
        if head.hasPrefix("document analysis") {
            return .init(summary: true, skills: true, narrativeCards: true, enrichment: true)
        }
        return nil
    }
}

extension AnthropicDocumentAnalysisService.PassSelection {
    /// Union of two selections (a pass runs if either selects it).
    func merged(with other: AnthropicDocumentAnalysisService.PassSelection) -> AnthropicDocumentAnalysisService.PassSelection {
        AnthropicDocumentAnalysisService.PassSelection(
            summary: summary || other.summary,
            skills: skills || other.skills,
            narrativeCards: narrativeCards || other.narrativeCards,
            enrichment: enrichment || other.enrichment
        )
    }

    /// True when no pass is selected.
    var isEmpty: Bool {
        !summary && !skills && !narrativeCards && !enrichment
    }
}
