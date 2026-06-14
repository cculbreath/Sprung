//
//  SmallModelsTests.swift
//  SprungTests
//
//  Pure-logic coverage for small value types:
//   - CardMetadata.defaults(fromFilename:) — extension/underscore/hyphen cleanup
//   - SearchPreferences / DiscoverySettings — defaults + Codable round-trip
//   - SourceCategory.defaultCadenceDays — pure enum mapping
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

    func testDiscoverySettingsDefaults() {
        let settings = DiscoverySettings()
        XCTAssertEqual(settings.llmModelId, "", "no hardcoded model id default")
        XCTAssertEqual(settings.reasoningEffort, "low")
        XCTAssertFalse(settings.useJobSearchCalendar)
        XCTAssertTrue(settings.dailyBriefingEnabled)
        XCTAssertEqual(settings.dailyBriefingHour, 8)
        XCTAssertEqual(settings.weeklyReviewDay, 6)
        XCTAssertEqual(settings.weeklyReviewHour, 16)
    }

    func testDiscoverySettingsCodableRoundTrip() throws {
        var settings = DiscoverySettings()
        settings.llmModelId = "some/model"
        settings.reasoningEffort = "high"
        settings.dailyBriefingHour = 7
        settings.jobSearchCalendarIdentifier = "cal-123"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DiscoverySettings.self, from: data)
        XCTAssertEqual(decoded.llmModelId, "some/model")
        XCTAssertEqual(decoded.reasoningEffort, "high")
        XCTAssertEqual(decoded.dailyBriefingHour, 7)
        XCTAssertEqual(decoded.jobSearchCalendarIdentifier, "cal-123")
    }

    // MARK: - SourceCategory.defaultCadenceDays

    func testSourceCategoryCadenceMapping() {
        XCTAssertEqual(SourceCategory.local.defaultCadenceDays, 3)
        XCTAssertEqual(SourceCategory.aggregator.defaultCadenceDays, 3)
        XCTAssertEqual(SourceCategory.industry.defaultCadenceDays, 4)
        XCTAssertEqual(SourceCategory.startup.defaultCadenceDays, 4)
        XCTAssertEqual(SourceCategory.companyDirect.defaultCadenceDays, 5)
        XCTAssertEqual(SourceCategory.staffing.defaultCadenceDays, 7)
        XCTAssertEqual(SourceCategory.networking.defaultCadenceDays, 7)
    }

    func testSourceCategoryEveryCaseHasPositiveCadence() {
        for category in SourceCategory.allCases {
            XCTAssertGreaterThan(category.defaultCadenceDays, 0, "\(category) needs a positive cadence")
        }
    }
}
