//
//  IntermediateRepresentationTests.swift
//  SprungTests
//
//  Guards the cache-prefix invariant: `renderedForExtraction()` becomes the
//  cached source block for every extraction pass, so for a given IR value it
//  MUST be byte-stable across calls AND across a JSON persistence round-trip,
//  and it must NEVER leak volatile provenance (timestamps, model ids) into the
//  cached text.
//

import XCTest
@testable import Sprung

final class IntermediateRepresentationTests: XCTestCase {

    // A provenance whose every field is a sentinel that must NOT appear in the
    // rendered extraction text.
    private static let sentinelProvenance = IRProvenance(
        sourceArtifactId: "PROVENANCE-ARTIFACT-SENTINEL",
        sha256: "PROVENANCE-SHA-SENTINEL",
        modelId: "PROVENANCE-MODEL-SENTINEL",
        promptVersion: "PROVENANCE-PROMPT-SENTINEL",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        analyzedCommit: "PROVENANCE-COMMIT-SENTINEL",
        explorationTurnCount: 42,
        toolVersions: "PROVENANCE-TOOLS-SENTINEL"
    )

    private func makePDFFixture() -> IntermediateRepresentation {
        let transcription = DocumentTranscription(
            fullText: "# Jane Doe\n\nSenior engineer with verbatim transcribed content.",
            visualElements: [
                VisualElement(
                    page: 2,
                    kind: "chart",
                    caption: "Revenue growth",
                    faithfulDescription: "Bar chart of revenue per quarter.",
                    dataPoints: ["Q1: $1.2M", "Q2: $1.8M"]
                ),
                VisualElement(
                    page: 1,
                    kind: "photo",
                    caption: nil,
                    faithfulDescription: "Headshot, top-right."
                )
            ],
            tables: [TranscribedTable(page: 3, markdown: "| Role | Year |\n|---|---|\n| Eng | 2020 |")],
            productionQuality: TranscriptionProductionQuality(
                typesettingSystemGuess: "LaTeX",
                typesettingEvidence: "Computer Modern glyphs; ligatures.",
                layoutSophistication: "Two-column, balanced.",
                columns: 2,
                typography: "Refined kerning.",
                colorAndGraphicDesignSignals: "Restrained accent color.",
                overallPolish: "High.",
                rationale: "Consistent baseline grid."
            ),
            structure: "p1: header; p2: experience; p3: skills",
            docMeta: DocMeta(pageCount: 3, language: "en", docClassGuess: "resume"),
            provenance: Self.sentinelProvenance
        )
        return .pdf(transcription)
    }

    private func makeGitFixture() -> IntermediateRepresentation {
        let digest = RepositoryDigest(
            repoName: "acme-engine",
            fileTree: "src/\n  main.swift\n  net/\n",
            languageStats: [
                LanguageStat(language: "Swift", loc: 12000, fileCount: 80, percent: 92.5),
                LanguageStat(language: "Shell", loc: 400, fileCount: 6, percent: 7.5)
            ],
            manifests: [RepoFile(path: "Package.swift", content: "// swift-tools-version:5.9\n")],
            readmeAndDocs: [RepoFile(path: "README.md", content: "# Acme Engine\n\nA streaming engine.")],
            entryPoints: ["Sources/acme/main.swift"],
            gitHistory: GitHistory(
                commitCount: 530,
                dateRange: "2021-2024",
                cadence: "weekly",
                topChurnFiles: ["src/net/router.swift"],
                branches: ["main", "dev"],
                tags: ["v1.0", "v2.0"]
            ),
            authorship: [ContributorShare(name: "jane", commitShare: 0.86, locShare: 0.91, blameOnCoreFiles: "owns router")],
            dependencyUsage: [DependencyUsage(dependency: "NIO", importCount: 142, usageNotes: "custom channel handlers")],
            architecture: "Actor-isolated streaming core with a NIO transport layer.",
            capabilities: ["Stream multiplexing", "Backpressure"],
            technicalHighlights: [
                TechnicalHighlight(
                    title: "Lock-free ring buffer",
                    description: "SPSC ring buffer for frame queueing.",
                    verbatimExcerpt: "func push(_ frame: Frame) { ... }",
                    path: "src/net/ring.swift",
                    lineRange: "20-60",
                    whyNotable: "Avoids allocation on the hot path."
                )
            ],
            codeExcerpts: [
                CodeExcerpt(
                    purpose: "Backpressure",
                    path: "src/net/router.swift",
                    lineRange: "100-130",
                    excerpt: "if window <= 0 { suspend() }",
                    tiedToClaim: "Backpressure"
                )
            ],
            productionQuality: RepoProductionQuality(
                testing: "XCTest, 0.7 test/src ratio",
                cicd: "GitHub Actions matrix build",
                lintFormatTypeSafety: "swiftformat + strict concurrency"
            ),
            skillSignals: [SkillSignal(skill: "SwiftNIO", strength: "strong", anchors: ["src/net/router.swift:100"])],
            omissions: "Vendored Submodules/ not examined (third-party).",
            provenance: Self.sentinelProvenance
        )
        return .git(digest)
    }

    // MARK: - Byte stability across repeated calls

    func testPDFRenderingIsStableAcrossCalls() {
        let ir = makePDFFixture()
        XCTAssertEqual(ir.renderedForExtraction(), ir.renderedForExtraction())
    }

    func testGitRenderingIsStableAcrossCalls() {
        let ir = makeGitFixture()
        XCTAssertEqual(ir.renderedForExtraction(), ir.renderedForExtraction())
    }

    // MARK: - Byte stability across the JSON persistence round-trip

    func testPDFRenderingSurvivesJSONRoundTrip() throws {
        try assertRenderingSurvivesRoundTrip(makePDFFixture())
    }

    func testGitRenderingSurvivesJSONRoundTrip() throws {
        try assertRenderingSurvivesRoundTrip(makeGitFixture())
    }

    private func assertRenderingSurvivesRoundTrip(_ ir: IntermediateRepresentation) throws {
        let before = ir.renderedForExtraction()
        // Round-trip through the PRODUCTION codec (ISO-8601 dates) — the exact
        // encode/decode pair every ingestion path and ArtifactRecord use.
        let json = try ir.encodedJSONString()
        let decoded = try XCTUnwrap(IntermediateRepresentation.decode(fromJSONString: json))
        XCTAssertEqual(before, decoded.renderedForExtraction(),
                       "renderedForExtraction must be byte-identical after a persistence round-trip")
        // And the encoded form itself must round-trip losslessly.
        let reDecoded = try XCTUnwrap(IntermediateRepresentation.decode(fromJSONString: decoded.encodedJSONString()))
        XCTAssertEqual(before, reDecoded.renderedForExtraction())
    }

    // MARK: - Provenance must never leak into the cached text

    func testRenderingExcludesProvenance() {
        for ir in [makePDFFixture(), makeGitFixture()] {
            let rendered = ir.renderedForExtraction()
            XCTAssertFalse(rendered.contains("PROVENANCE-"),
                           "Volatile provenance leaked into the cached extraction text")
            XCTAssertFalse(rendered.contains("1700000000"),
                           "A timestamp leaked into the cached extraction text")
        }
    }

    // MARK: - fullText routes to the verbatim transcription for PDFs

    func testPDFFullTextIsVerbatimTranscription() {
        let ir = makePDFFixture()
        XCTAssertTrue(ir.fullText.contains("verbatim transcribed content"))
    }

    func testIsPaged() {
        XCTAssertTrue(makePDFFixture().isPaged)
        XCTAssertFalse(makeGitFixture().isPaged)
    }
}
