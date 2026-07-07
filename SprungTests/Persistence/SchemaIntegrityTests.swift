//
//  SchemaIntegrityTests.swift
//  SprungTests
//
//  Phase 3: SwiftData persistence — schema completeness guard. Asserts the canonical
//  schema builds an in-memory container and that the model set stays non-trivial.
//  Deliberately does NOT call ModelContainer.createWithMigration() (that opens the
//  real on-disk store).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class SchemaIntegrityTests: XCTestCase {

    func testInMemoryContainerBuildsFromCanonicalSchema() throws {
        let container = try ModelContainer(
            for: SprungSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        XCTAssertNotNil(container)
    }

    func testModelSetIsNonTrivial() {
        // The schema is documented to carry ~28 models. Guard against an accidental
        // truncation of the registration list without hard-coding the exact count.
        XCTAssertGreaterThanOrEqual(
            SprungSchema.models.count, 20,
            "SprungSchema.models looks truncated — expected the full registration list"
        )
    }

    func testCoreModelsAreRegistered() {
        let registered = Set(SprungSchema.models.map { String(describing: $0) })
        let required = [
            "JobApp", "Resume", "KnowledgeCard", "Skill", "CoverLetter",
            "ApplicantProfile", "ExperienceDefaults", "Template", "EnabledLLM",
            "OnboardingSession", "ArtifactRecord", "CandidateDossier",
            "TitleSetRecord", "CoverRef"
        ]
        for model in required {
            XCTAssertTrue(registered.contains(model), "\(model) must be registered in SprungSchema.models")
        }
    }

    func testSchemaHasNoDuplicateModelRegistrations() {
        let names = SprungSchema.models.map { String(describing: $0) }
        XCTAssertEqual(names.count, Set(names).count, "duplicate model registration in SprungSchema.models")
    }
}
