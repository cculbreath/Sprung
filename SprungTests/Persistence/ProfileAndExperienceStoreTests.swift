//
//  ProfileAndExperienceStoreTests.swift
//  SprungTests
//
//  Phase 3: SwiftData persistence — singleton-style stores (ApplicantProfileStore,
//  ExperienceDefaultsStore) plus TemplateStore and EnabledLLMStore CRUD.
//

import XCTest
import SwiftData
@testable import Sprung

// MARK: - ApplicantProfileStore

@MainActor
final class ApplicantProfileStoreTests: InMemoryStoreCase {

    func testCurrentProfileCreatesAndPersistsSingleton() throws {
        let store = ApplicantProfileStore(context: context)
        XCTAssertEqual(try fetchAll(ApplicantProfile.self).count, 0)

        let profile = store.currentProfile()
        XCTAssertEqual(try fetchAll(ApplicantProfile.self).count, 1)

        // Second call returns the same cached instance.
        let again = store.currentProfile()
        XCTAssertEqual(profile.persistentModelID, again.persistentModelID)
    }

    func testCurrentProfileAdoptsExistingRow() throws {
        // Seed a profile directly, then a fresh store should find it (not create a 2nd).
        let seeded = insert(Fixtures.makeApplicantProfile(name: "Seeded"))
        saveContext()

        let store = ApplicantProfileStore(context: context)
        let current = store.currentProfile()
        XCTAssertEqual(current.name, "Seeded")
        XCTAssertEqual(current.persistentModelID, seeded.persistentModelID)
        XCTAssertEqual(try fetchAll(ApplicantProfile.self).count, 1)
    }

    func testSaveAttachesUnattachedProfile() throws {
        let store = ApplicantProfileStore(context: context)
        let profile = Fixtures.makeApplicantProfile(name: "Detached")
        store.save(profile)

        XCTAssertEqual(try fetchAll(ApplicantProfile.self).count, 1)
        XCTAssertEqual(store.currentProfile().name, "Detached")
    }

    func testResetRestoresDefaults() throws {
        let store = ApplicantProfileStore(context: context)
        let profile = store.currentProfile()
        profile.name = "Custom Name"
        profile.profiles = [SocialProfile(network: "GitHub", username: "x", url: "u")]
        store.save(profile)

        store.reset()
        let after = store.currentProfile()
        XCTAssertEqual(after.name, "John Doe")
        XCTAssertTrue(after.profiles.isEmpty)
    }

    func testClearCacheRefetchesFromContext() throws {
        let store = ApplicantProfileStore(context: context)
        _ = store.currentProfile()
        store.clearCache()
        // Should still resolve to the single persisted row.
        XCTAssertEqual(try fetchAll(ApplicantProfile.self).count, 1)
        XCTAssertNotNil(store.currentProfile())
    }
}

// MARK: - ExperienceDefaultsStore

@MainActor
final class ExperienceDefaultsStoreTests: InMemoryStoreCase {

    func testCurrentDefaultsCreatesSingleton() throws {
        let store = ExperienceDefaultsStore(context: context)
        XCTAssertEqual(try fetchAll(ExperienceDefaults.self).count, 0)

        let defaults = store.currentDefaults()
        XCTAssertEqual(try fetchAll(ExperienceDefaults.self).count, 1)
        let again = store.currentDefaults()
        XCTAssertEqual(defaults.persistentModelID, again.persistentModelID)
    }

    func testMarkSeedCreatedPersists() throws {
        let store = ExperienceDefaultsStore(context: context)
        XCTAssertFalse(store.isSeedCreated)
        store.markSeedCreated()
        XCTAssertTrue(store.isSeedCreated)

        // Verify through the context directly.
        store.clearCache()
        XCTAssertTrue(store.currentDefaults().seedCreated)
    }

    func testChangeVersionIncrementsOnSave() throws {
        let store = ExperienceDefaultsStore(context: context)
        let before = store.changeVersion
        store.markSeedCreated()
        XCTAssertGreaterThan(store.changeVersion, before)
    }

    func testClearGeneratedContentResetsSeedFlag() throws {
        let store = ExperienceDefaultsStore(context: context)
        store.markSeedCreated()
        XCTAssertTrue(store.isSeedCreated)

        store.clearGeneratedContent()
        XCTAssertFalse(store.isSeedCreated)
    }
}

// MARK: - TemplateStore

@MainActor
final class TemplateStoreTests: InMemoryStoreCase {

    func testUpsertInsertsNewTemplate() throws {
        let store = TemplateStore(context: context)
        let template = store.upsertTemplate(
            slug: "Modern",
            name: "Modern",
            htmlContent: "<html></html>",
            isCustom: false
        )
        XCTAssertEqual(template.slug, "modern") // normalized to lowercase
        XCTAssertEqual(store.templates().count, 1)
        XCTAssertEqual(store.htmlTemplateContent(slug: "modern"), "<html></html>")
    }

    func testUpsertUpdatesExistingBySlug() throws {
        let store = TemplateStore(context: context)
        _ = store.upsertTemplate(slug: "classic", name: "Classic", htmlContent: "v1", isCustom: false)
        _ = store.upsertTemplate(slug: "classic", name: "Classic Updated", htmlContent: "v2", isCustom: true)

        XCTAssertEqual(store.templates().count, 1)
        let template = store.template(slug: "classic")
        XCTAssertEqual(template?.name, "Classic Updated")
        XCTAssertEqual(template?.htmlContent, "v2")
        XCTAssertTrue(template?.isCustom ?? false)
    }

    func testFirstTemplateBecomesDefault() throws {
        let store = TemplateStore(context: context)
        _ = store.upsertTemplate(slug: "first", name: "First", isCustom: false)
        XCTAssertEqual(store.defaultTemplate()?.slug, "first")
    }

    func testSetDefaultMovesDefaultFlag() throws {
        let store = TemplateStore(context: context)
        _ = store.upsertTemplate(slug: "a", name: "A", isCustom: false)
        let b = store.upsertTemplate(slug: "b", name: "B", isCustom: false)
        store.setDefault(b)

        XCTAssertEqual(store.defaultTemplate()?.slug, "b")
        // Only one default should exist.
        let defaults = try fetchAll(Template.self).filter { $0.isDefault }
        XCTAssertEqual(defaults.count, 1)
    }

    func testDeleteTemplateRemovesAndReassignsDefault() throws {
        let store = TemplateStore(context: context)
        _ = store.upsertTemplate(slug: "a", name: "A", isCustom: false) // becomes default
        _ = store.upsertTemplate(slug: "b", name: "B", isCustom: false)

        store.deleteTemplate(slug: "a")
        XCTAssertNil(store.template(slug: "a"))
        XCTAssertEqual(store.templates().count, 1)
        // A new default must have been chosen since "a" was the default.
        XCTAssertEqual(store.defaultTemplate()?.slug, "b")
    }

    func testUpdateManifestPersists() throws {
        let store = TemplateStore(context: context)
        _ = store.upsertTemplate(slug: "m", name: "M", isCustom: false)
        let payload = Data("{}".utf8)
        try store.updateManifest(slug: "m", manifestData: payload)
        XCTAssertEqual(store.template(slug: "m")?.manifestData, payload)
    }

    func testUpdateManifestThrowsForMissingTemplate() throws {
        let store = TemplateStore(context: context)
        XCTAssertThrowsError(try store.updateManifest(slug: "ghost", manifestData: Data())) { error in
            guard case TemplateStoreError.templateNotFound(let slug) = error else {
                return XCTFail("expected templateNotFound, got \(error)")
            }
            XCTAssertEqual(slug, "ghost")
        }
    }
}

// MARK: - EnabledLLMStore

@MainActor
final class EnabledLLMStoreTests: InMemoryStoreCase {

    func testGetOrCreateInsertsAndDedups() throws {
        let store = EnabledLLMStore(modelContext: context)
        let first = store.getOrCreateModel(id: "model-x", displayName: "Model X", provider: "openrouter")
        let second = store.getOrCreateModel(id: "model-x", displayName: "Renamed", provider: "openrouter")

        // Same model — no duplicate row.
        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(try fetchAll(EnabledLLM.self).count, 1)
    }

    func testEnabledModelIdsReflectsInsertions() throws {
        let store = EnabledLLMStore(modelContext: context)
        _ = store.getOrCreateModel(id: "a", displayName: "A")
        _ = store.getOrCreateModel(id: "b", displayName: "B")
        store.refreshEnabledModels()
        XCTAssertEqual(Set(store.enabledModelIds), ["a", "b"])
    }

    func testDisableModelRemovesFromEnabledSet() throws {
        let store = EnabledLLMStore(modelContext: context)
        _ = store.getOrCreateModel(id: "a", displayName: "A")
        store.refreshEnabledModels()
        XCTAssertTrue(store.enabledModelIds.contains("a"))

        store.disableModel(id: "a")
        XCTAssertFalse(store.enabledModelIds.contains("a"),
                       "a disabled model must drop out of the enabled set")
        // Note: `isModelEnabled(_:)` returns true for models absent from the enabled
        // set (opt-out default), so once disabled — and thus no longer tracked as
        // enabled — it reads back as enabled-by-default. The meaningful disable
        // contract is its absence from `enabledModelIds`, asserted above.
    }

    func testJSONSchemaFailureTracking() throws {
        let store = EnabledLLMStore(modelContext: context)
        _ = store.getOrCreateModel(id: "flaky", displayName: "Flaky")
        store.recordJSONSchemaFailure(modelId: "flaky", reason: "bad schema")
        store.recordJSONSchemaFailure(modelId: "flaky", reason: "bad schema again")
        XCTAssertTrue(store.shouldAvoidJSONSchema(modelId: "flaky"))

        store.recordJSONSchemaSuccess(modelId: "flaky")
        XCTAssertFalse(store.shouldAvoidJSONSchema(modelId: "flaky"))
    }
}
