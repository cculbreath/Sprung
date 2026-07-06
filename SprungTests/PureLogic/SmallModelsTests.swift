//
//  SmallModelsTests.swift
//  SprungTests
//
//  Pure-logic coverage for small value types:
//   - CardMetadata.defaults(fromFilename:) — extension/underscore/hyphen cleanup
//   - SearchPreferences — defaults + Codable round-trip
//   - DiscoverySettings — Codable round-trip + tolerance of removed legacy keys
//
//  NOTE: SearchPreferences.load()/save() and DiscoverySettings.load()/save()
//  hardcode UserDefaults.standard, so they are NOT exercised here (would mutate
//  the shared domain). Only the Codable shape and defaults are tested directly.
//

import XCTest
@testable import Sprung

final class SmallModelsTests: XCTestCase {

    // MARK: - CardMetadata.defaults(fromFilename:)

    func testCardMetadataStripsPdfExtension() {
        let meta = CardMetadata.defaults(fromFilename: "resume.pdf")
        XCTAssertEqual(meta.title, "resume")
        XCTAssertEqual(meta.cardType, "project", "default card type is project")
        XCTAssertNil(meta.organization)
        XCTAssertNil(meta.timePeriod)
        XCTAssertNil(meta.location)
    }

    func testCardMetadataStripsDocxAndTxt() {
        XCTAssertEqual(CardMetadata.defaults(fromFilename: "cover.docx").title, "cover")
        XCTAssertEqual(CardMetadata.defaults(fromFilename: "notes.txt").title, "notes")
    }

    func testCardMetadataReplacesUnderscoresAndHyphens() {
        let meta = CardMetadata.defaults(fromFilename: "my_great-project.pdf")
        XCTAssertEqual(meta.title, "my great project")
    }

    func testCardMetadataPlainNameUnchanged() {
        XCTAssertEqual(CardMetadata.defaults(fromFilename: "Portfolio").title, "Portfolio")
    }

    // MARK: - SearchPreferences

    func testSearchPreferencesDefaults() {
        let prefs = SearchPreferences()
        XCTAssertTrue(prefs.targetSectors.isEmpty)
        XCTAssertEqual(prefs.primaryLocation, "")
        XCTAssertFalse(prefs.remoteAcceptable)
        XCTAssertFalse(prefs.willingToRelocate)
        XCTAssertEqual(prefs.preferredArrangement, .hybrid)
        XCTAssertEqual(prefs.companySizePreference, .any)
        XCTAssertEqual(prefs.weeklyApplicationTarget, 5)
        XCTAssertEqual(prefs.weeklyNetworkingTarget, 2)
    }

    func testSearchPreferencesCodableRoundTrip() throws {
        var prefs = SearchPreferences()
        prefs.targetSectors = ["fintech", "health"]
        prefs.primaryLocation = "Austin, TX"
        prefs.remoteAcceptable = true
        prefs.weeklyApplicationTarget = 9
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(SearchPreferences.self, from: data)
        XCTAssertEqual(decoded.targetSectors, ["fintech", "health"])
        XCTAssertEqual(decoded.primaryLocation, "Austin, TX")
        XCTAssertTrue(decoded.remoteAcceptable)
        XCTAssertEqual(decoded.weeklyApplicationTarget, 9)
    }

    // MARK: - DiscoverySettings

    /// The 2026-07 dead-settings sweep removed the notification, calendar, and
    /// OpenAI-model fields from `DiscoverySettings`. Blobs saved by older builds
    /// still carry those keys; synthesized `Decodable` ignores unknown JSON keys,
    /// so existing stored settings must keep decoding. This pins that contract.
    func testDiscoverySettingsDecodingIgnoresRemovedLegacyKeys() throws {
        let legacyJSON = """
        {
            "llmModelId": "some/model",
            "reasoningEffort": "high",
            "useJobSearchCalendar": true,
            "jobSearchCalendarIdentifier": "cal-123",
            "notificationsEnabled": true,
            "dailyBriefingEnabled": true,
            "dailyBriefingHour": 7,
            "dailyBriefingMinute": 30,
            "followUpRemindersEnabled": true,
            "weeklyReviewEnabled": true,
            "weeklyReviewDay": 6,
            "weeklyReviewHour": 16,
            "weeklyReviewMinute": 0,
            "notificationFatiguePauseOffered": false,
            "createdAt": 700000000,
            "updatedAt": 700000001
        }
        """
        let decoded = try JSONDecoder().decode(DiscoverySettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSinceReferenceDate: 700000000))
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSinceReferenceDate: 700000001))
    }

    func testDiscoverySettingsCodableRoundTrip() throws {
        let settings = DiscoverySettings()
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DiscoverySettings.self, from: data)
        XCTAssertEqual(
            decoded.createdAt.timeIntervalSinceReferenceDate,
            settings.createdAt.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
    }
}
