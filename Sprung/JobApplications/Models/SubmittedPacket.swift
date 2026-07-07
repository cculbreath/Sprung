//
//  SubmittedPacket.swift
//  Sprung
//
//  A frozen record of what was actually submitted for a job application
//  (app-audit 2026-07-06, resume-editor #2). Every resume edit overwrites
//  `Resume.pdfData` and exports vanish into ~/Downloads, so the single most
//  consequential artifact of the pipeline — the packet the company received —
//  was the one thing not tracked. A packet is minted at the "Mark as Submitted"
//  moment and at "Export Application", capturing a FRESH render (never the
//  possibly-stale `resume.pdfData`) plus a structured tree snapshot, so weeks
//  later at interview-prep time the user can see exactly what they sent.
//
import Foundation
import SwiftData

@Model
final class SubmittedPacket: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    /// The `JobApp.id` this packet was submitted for. Denormalized (rather than
    /// a relationship) so the read accessor predicates on a plain UUID — robust
    /// and independent of relationship-graph traversal.
    var jobAppId: UUID

    /// When the packet was frozen.
    var submittedDate: Date = Date()

    /// The rendered PDF bytes at submit time — the authoritative "what was sent"
    /// artifact. Captured from a fresh render, never a stale `resume.pdfData`.
    @Attribute(.externalStorage)
    var resumePdfData: Data

    /// Structured snapshot of the resume tree at submit time, serialized with the
    /// same encoder the revision workspace uses (`TreeNode.toRevisionDictionary`,
    /// pretty-printed + sorted keys). A backup of the content behind the PDF.
    @Attribute(.externalStorage)
    var treeSnapshotData: Data?

    /// The cover-letter text submitted alongside the resume, if any.
    var coverLetterText: String?

    /// The template slug the PDF was rendered with.
    var templateSlug: String

    /// Human label carried from the resume's provenance (`Resume.label`), e.g.
    /// "Aleo — AI revised", so a packet row is identifiable at a glance.
    var label: String

    init(
        jobAppId: UUID,
        submittedDate: Date = Date(),
        resumePdfData: Data,
        treeSnapshotData: Data? = nil,
        coverLetterText: String? = nil,
        templateSlug: String,
        label: String
    ) {
        self.jobAppId = jobAppId
        self.submittedDate = submittedDate
        self.resumePdfData = resumePdfData
        self.treeSnapshotData = treeSnapshotData
        self.coverLetterText = coverLetterText
        self.templateSlug = templateSlug
        self.label = label
    }
}
