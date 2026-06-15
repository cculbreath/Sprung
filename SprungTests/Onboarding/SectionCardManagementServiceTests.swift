//
//  SectionCardManagementServiceTests.swift
//  SprungTests
//
//  Pure-domain tests for SectionCardManagementService — the actor that mints ids and
//  shapes the result JSON for non-chronological cards (awards / languages / references
//  and publications). It has a single clean dependency (EventCoordinator, no-arg init),
//  so it is constructible in isolation.
//
//  We assert the return contract (status/success/id/sectionType/count) and the
//  id-minting behaviour: a card without an `id` gets one minted; a card that already
//  carries an `id` keeps it; and under a bound determinism scope the minted ids come
//  from the recorded sequence (the replay-fidelity property, at the service level).
//

import XCTest
import SwiftyJSON
@testable import Sprung

final class SectionCardManagementServiceTests: XCTestCase {

    private func makeService() -> SectionCardManagementService {
        SectionCardManagementService(eventBus: EventCoordinator())
    }

    // MARK: - Section cards: create

    func testCreateSectionCardMintsIdAndReturnsContract() async {
        let service = makeService()
        var fields = JSON()
        fields["title"].string = "Best Paper Award"

        let result = await service.createSectionCard(sectionType: "award", fields: fields)

        XCTAssertEqual(result["status"].string, "completed")
        XCTAssertTrue(result["success"].boolValue)
        XCTAssertEqual(result["sectionType"].string, "award")
        let id = result["id"].string
        XCTAssertNotNil(id, "a freshly-created section card must be assigned an id")
        XCTAssertNotNil(UUID(uuidString: id ?? ""), "minted id (no scope) is a plain UUID string")
    }

    func testCreateSectionCardPreservesCallerSuppliedId() async {
        let service = makeService()
        var fields = JSON()
        fields["title"].string = "Award"
        fields["id"].string = "caller-provided-id"

        let result = await service.createSectionCard(sectionType: "award", fields: fields)
        XCTAssertEqual(result["id"].string, "caller-provided-id",
                       "an id already present on the fields must NOT be overwritten")
    }

    // MARK: - Section cards: update / delete

    func testUpdateSectionCardEchoesId() async {
        let service = makeService()
        let result = await service.updateSectionCard(id: "sec-1", sectionType: "language",
                                                     fields: JSON(["fluency": "native"]))
        XCTAssertEqual(result["status"].string, "completed")
        XCTAssertTrue(result["success"].boolValue)
        XCTAssertEqual(result["id"].string, "sec-1")
    }

    func testDeleteSectionCardEchoesId() async {
        let service = makeService()
        let result = await service.deleteSectionCard(id: "sec-2", sectionType: "reference")
        XCTAssertEqual(result["status"].string, "completed")
        XCTAssertTrue(result["success"].boolValue)
        XCTAssertEqual(result["id"].string, "sec-2")
    }

    // MARK: - Publication cards: create / update / delete / import

    func testCreatePublicationCardMintsIdAndReturnsContract() async {
        let service = makeService()
        var fields = JSON()
        fields["name"].string = "On Computable Numbers"

        let result = await service.createPublicationCard(fields: fields)   // default sourceType
        XCTAssertEqual(result["status"].string, "completed")
        XCTAssertTrue(result["success"].boolValue)
        let id = result["id"].string
        XCTAssertNotNil(id)
        XCTAssertNotNil(UUID(uuidString: id ?? ""))
    }

    func testCreatePublicationCardPreservesCallerSuppliedId() async {
        let service = makeService()
        var fields = JSON()
        fields["name"].string = "Paper"
        fields["id"].string = "pub-fixed"
        let result = await service.createPublicationCard(fields: fields, sourceType: "bibtex")
        XCTAssertEqual(result["id"].string, "pub-fixed")
    }

    func testUpdatePublicationCardEchoesId() async {
        let service = makeService()
        let result = await service.updatePublicationCard(id: "pub-1", fields: JSON(["doi": "10.1/x"]))
        XCTAssertEqual(result["id"].string, "pub-1")
        XCTAssertTrue(result["success"].boolValue)
    }

    func testDeletePublicationCardEchoesId() async {
        let service = makeService()
        let result = await service.deletePublicationCard(id: "pub-2")
        XCTAssertEqual(result["id"].string, "pub-2")
        XCTAssertTrue(result["success"].boolValue)
    }

    func testImportPublicationCardsReturnsCount() async {
        let service = makeService()
        let cards = [JSON(["name": "A"]), JSON(["name": "B"]), JSON(["name": "C"])]
        let result = await service.importPublicationCards(cards: cards, sourceType: "bibtex")
        XCTAssertEqual(result["status"].string, "completed")
        XCTAssertTrue(result["success"].boolValue)
        XCTAssertEqual(result["count"].int, 3)
        XCTAssertEqual(result["sourceType"].string, "bibtex")
    }

    // MARK: - Determinism seam at the service level

    /// Minting two section cards under a `.recording` scope captures both ids in order;
    /// replaying that captured sequence reproduces the exact same ids — so a later
    /// "update/delete by id" turn keeps hitting the right card after re-execution.
    func testCardIdsAreDeterministicUnderRecordThenReplay() async {
        // Record: mint ids for two created cards.
        let recording = DeterminismContext(mode: .recording)
        let recordedIds: [String] = await DeterminismScope.$current.withValue(recording) {
            let service = makeService()
            let a = await service.createSectionCard(sectionType: "award", fields: JSON(["title": "A"]))
            let b = await service.createPublicationCard(fields: JSON(["name": "B"]))
            return [a["id"].stringValue, b["id"].stringValue]
        }
        XCTAssertEqual(recording.mintedIds, recordedIds, "recording must capture exactly the minted ids")

        // Replay: seed a fresh service run with the captured sequence.
        let replaying = DeterminismContext(mode: .replaying(recording.mintedIds))
        let replayedIds: [String] = await DeterminismScope.$current.withValue(replaying) {
            let service = makeService()
            let a = await service.createSectionCard(sectionType: "award", fields: JSON(["title": "A"]))
            let b = await service.createPublicationCard(fields: JSON(["name": "B"]))
            return [a["id"].stringValue, b["id"].stringValue]
        }
        XCTAssertEqual(replayedIds, recordedIds, "replay must reproduce the recorded card ids exactly")
        XCTAssertFalse(replaying.didExhaust)
    }
}
