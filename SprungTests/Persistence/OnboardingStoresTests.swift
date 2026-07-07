//
//  OnboardingStoresTests.swift
//  SprungTests
//
//  Phase 3: SwiftData persistence — CRUD for the onboarding/dossier/guidance store
//  family. All take `init(context:)` (or `init(modelContext:)` for EnabledLLM,
//  covered elsewhere).
//

import XCTest
import SwiftData
@testable import Sprung

// MARK: - OnboardingSessionStore

@MainActor
final class OnboardingSessionStoreTests: InMemoryStoreCase {

    func testCreateSessionPersists() throws {
        let store = OnboardingSessionStore(context: context)
        let session = store.createSession()

        XCTAssertEqual(try fetchAll(OnboardingSession.self).count, 1)
        XCTAssertFalse(session.isComplete)
        XCTAssertEqual(store.getActiveSession()?.persistentModelID, session.persistentModelID)
    }

    func testCompleteSessionRemovesFromActive() throws {
        let store = OnboardingSessionStore(context: context)
        let session = store.createSession()
        store.completeSession(session)

        XCTAssertTrue(session.isComplete)
        XCTAssertNil(store.getActiveSession())
        // Still persisted, just not "active".
        XCTAssertEqual(store.getAllSessions().count, 1)
    }

    func testDeleteSessionRemovesIt() throws {
        let store = OnboardingSessionStore(context: context)
        let session = store.createSession()
        store.deleteSession(session)
        XCTAssertEqual(try fetchAll(OnboardingSession.self).count, 0)
    }

    func testAddMessageAttachesToSession() throws {
        let store = OnboardingSessionStore(context: context)
        let session = store.createSession()
        _ = store.addMessage(session, role: "user", text: "hello")
        _ = store.addMessage(session, role: "assistant", text: "hi there")
        store.saveMessages()

        let messages = store.getMessages(session)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.text, "hello")
        XCTAssertEqual(try fetchAll(OnboardingMessageRecord.self).count, 2)
    }

    func testUpdateObjectiveCreatesAndUpdates() throws {
        let store = OnboardingSessionStore(context: context)
        let session = store.createSession()
        store.updateObjective(session, objectiveId: "obj-1", status: "in_progress")
        XCTAssertEqual(store.getObjectives(session).count, 1)

        store.updateObjective(session, objectiveId: "obj-1", status: "complete")
        XCTAssertEqual(store.getObjectives(session).count, 1) // updated, not duplicated
        XCTAssertEqual(store.restoreObjectiveStatuses(session)["obj-1"], "complete")
    }

    func testUpdatePhasePersists() throws {
        let store = OnboardingSessionStore(context: context)
        let session = store.createSession()
        store.updatePhase(session, phase: "phase2_documents")
        XCTAssertEqual(session.phase, "phase2_documents")
    }

    func testSkeletonTimelineRoundTrip() throws {
        let store = OnboardingSessionStore(context: context)
        let session = store.createSession()
        store.updateSkeletonTimeline(session, timelineJSON: "{\"entries\":[]}")
        XCTAssertEqual(store.getSkeletonTimeline(session), "{\"entries\":[]}")
    }
}

// MARK: - ArtifactRecordStore

@MainActor
final class ArtifactRecordStoreTests: InMemoryStoreCase {

    func testAddArtifactToSession() throws {
        let sessionStore = OnboardingSessionStore(context: context)
        let artifactStore = ArtifactRecordStore(context: context)
        let session = sessionStore.createSession()

        let artifact = artifactStore.addArtifact(
            to: session,
            sourceType: "pdf",
            filename: "resume.pdf",
            extractedContent: "some text"
        )
        XCTAssertEqual(artifactStore.allArtifacts.count, 1)
        XCTAssertEqual(artifactStore.artifacts(for: session).count, 1)
        XCTAssertFalse(artifact.isArchived)
        XCTAssertEqual(artifact.displayName, "resume.pdf")
    }

    func testStandaloneArtifactIsArchived() throws {
        let store = ArtifactRecordStore(context: context)
        let artifact = store.addStandaloneArtifact(
            sourceType: "git",
            filename: "repo",
            extractedContent: "digest"
        )
        XCTAssertTrue(artifact.isArchived)
        XCTAssertEqual(store.archivedArtifacts.count, 1)
    }

    func testFindByIdAndSha256() throws {
        let store = ArtifactRecordStore(context: context)
        let artifact = store.addStandaloneArtifact(
            sourceType: "pdf",
            filename: "doc.pdf",
            extractedContent: "x",
            sha256: "deadbeef"
        )
        XCTAssertEqual(store.artifact(byId: artifact.id)?.persistentModelID, artifact.persistentModelID)
        XCTAssertEqual(store.artifact(bySha256: "deadbeef")?.persistentModelID, artifact.persistentModelID)
        XCTAssertNil(store.artifact(bySha256: "missing"))
    }

    func testPromoteAndDemoteArtifact() throws {
        let sessionStore = OnboardingSessionStore(context: context)
        let store = ArtifactRecordStore(context: context)
        let session = sessionStore.createSession()
        let artifact = store.addStandaloneArtifact(
            sourceType: "pdf",
            filename: "f.pdf",
            extractedContent: "x"
        )
        XCTAssertTrue(artifact.isArchived)

        store.promoteArtifact(artifact, to: session)
        XCTAssertFalse(artifact.isArchived)
        XCTAssertEqual(store.artifacts(for: session).count, 1)

        store.demoteArtifact(artifact)
        XCTAssertTrue(artifact.isArchived)
    }

    func testDeleteArtifactByIdString() throws {
        let store = ArtifactRecordStore(context: context)
        let artifact = store.addStandaloneArtifact(
            sourceType: "pdf",
            filename: "del.pdf",
            extractedContent: "x"
        )
        XCTAssertTrue(store.deleteArtifact(byIdString: artifact.id.uuidString))
        XCTAssertEqual(store.allArtifacts.count, 0)
        XCTAssertFalse(store.deleteArtifact(byIdString: "not-a-uuid"))
    }

    func testKnowledgeExtractionFiltering() throws {
        let store = ArtifactRecordStore(context: context)
        _ = store.addStandaloneArtifact(
            sourceType: "pdf",
            filename: "withskills.pdf",
            extractedContent: "x",
            skillsJSON: "[{\"canonical\":\"Swift\"}]"
        )
        _ = store.addStandaloneArtifact(
            sourceType: "pdf",
            filename: "plain.pdf",
            extractedContent: "x"
        )
        XCTAssertEqual(store.artifactsWithSkills().count, 1)
        XCTAssertEqual(store.artifactsWithKnowledgeExtraction().count, 1)
    }
}

// MARK: - CandidateDossierStore

@MainActor
final class CandidateDossierStoreTests: InMemoryStoreCase {

    func testUpsertCreatesSingletonThenUpdates() throws {
        let store = CandidateDossierStore(context: context)
        XCTAssertFalse(store.hasDossier)

        let created = store.upsertDossier(jobSearchContext: "Looking for staff roles.")
        XCTAssertTrue(store.hasDossier)
        XCTAssertEqual(try fetchAll(CandidateDossier.self).count, 1)

        let updated = store.upsertDossier(jobSearchContext: "Updated context.")
        XCTAssertEqual(created.persistentModelID, updated.persistentModelID)
        XCTAssertEqual(try fetchAll(CandidateDossier.self).count, 1)
        XCTAssertEqual(store.dossier?.jobSearchContext, "Updated context.")
    }

    func testUpdateSectionCreatesAndPopulates() throws {
        let store = CandidateDossierStore(context: context)
        store.updateSection(.strengths, content: "Strong systems thinker.")
        XCTAssertEqual(store.sectionContent(.strengths), "Strong systems thinker.")
        XCTAssertTrue(store.dossier?.strengthsToEmphasize?.isEmpty == false)
    }

    func testMissingSectionsReportsRequired() throws {
        let store = CandidateDossierStore(context: context)
        // Job context too short to be complete.
        store.upsertDossier(jobSearchContext: "short")
        let missing = Set(store.missingSections())
        XCTAssertTrue(missing.contains(.jobContext))
        XCTAssertTrue(missing.contains(.strengths))
        XCTAssertTrue(missing.contains(.pitfalls))
    }

    func testDeleteDossier() throws {
        let store = CandidateDossierStore(context: context)
        store.upsertDossier(jobSearchContext: "x")
        store.deleteDossier()
        XCTAssertFalse(store.hasDossier)
        XCTAssertEqual(try fetchAll(CandidateDossier.self).count, 0)
    }
}

// MARK: - TitleSetStore

@MainActor
final class TitleSetStoreTests: InMemoryStoreCase {

    private func makeRecord(words: [String] = ["Physicist", "Developer"]) -> TitleSetRecord {
        TitleSetRecord(words: words.map { TitleWord(text: $0) })
    }

    func testAddAndCacheRefresh() throws {
        let store = TitleSetStore(context: context)
        XCTAssertFalse(store.hasTitleSets)

        let record = makeRecord()
        store.add(record)
        XCTAssertTrue(store.hasTitleSets)
        XCTAssertEqual(store.titleSetCount, 1)
        XCTAssertEqual(store.titleSet(for: record.id)?.persistentModelID, record.persistentModelID)
    }

    func testWordsJSONRoundTrips() throws {
        let store = TitleSetStore(context: context)
        let record = makeRecord(words: ["Engineer", "Educator", "Machinist"])
        store.add(record)

        let fetched = try fetchAll(TitleSetRecord.self).first
        XCTAssertEqual(fetched?.words.map(\.text), ["Engineer", "Educator", "Machinist"])
    }

    func testDeleteAndDeleteAll() throws {
        let store = TitleSetStore(context: context)
        let a = makeRecord(words: ["A"])
        let b = makeRecord(words: ["B"])
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.titleSetCount, 2)

        store.delete(a)
        XCTAssertEqual(store.titleSetCount, 1)

        store.deleteAll()
        XCTAssertEqual(store.titleSetCount, 0)
        XCTAssertEqual(try fetchAll(TitleSetRecord.self).count, 0)
    }

    func testAddGenerationTurnPersistsHistory() throws {
        let store = TitleSetStore(context: context)
        let record = makeRecord()
        store.add(record)
        store.addGenerationTurn(to: record, turn: GenerationTurn(generatedWords: ["X", "Y"]))

        let fetched = try fetchAll(TitleSetRecord.self).first
        XCTAssertEqual(fetched?.history.count, 1)
        XCTAssertEqual(fetched?.history.first?.generatedWords, ["X", "Y"])
    }
}

// MARK: - CoverRefStore

@MainActor
final class CoverRefStoreTests: InMemoryStoreCase {

    func testAddAndDeleteCoverRef() throws {
        let store = CoverRefStore(context: context)
        let ref = CoverRef(name: "Sample", content: "My voice.", enabledByDefault: true, type: .writingSample)
        store.addCoverRef(ref)

        XCTAssertEqual(store.storedCoverRefs.count, 1)
        XCTAssertEqual(store.defaultSources.count, 1)

        store.deleteCoverRef(ref)
        XCTAssertEqual(store.storedCoverRefs.count, 0)
    }

    func testVoiceSamplesCapsAtThreeEnabledWritingSamples() throws {
        let store = CoverRefStore(context: context)
        for index in 0..<5 {
            store.addCoverRef(
                CoverRef(name: "S\(index)", content: "c", enabledByDefault: true, type: .writingSample)
            )
        }
        // Non-default and non-writing-sample refs should be excluded.
        store.addCoverRef(CoverRef(name: "Off", content: "c", enabledByDefault: false, type: .writingSample))
        store.addCoverRef(CoverRef(name: "Primer", content: "c", enabledByDefault: true, type: .voicePrimer))

        let samples = CoverRefStore.voiceSamples(in: store.storedCoverRefs)
        XCTAssertEqual(samples.count, 3)
        XCTAssertTrue(samples.allSatisfy { $0.type == .writingSample && $0.enabledByDefault })
    }
}
