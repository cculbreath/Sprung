//
//  SmallModelsTests.swift
//  SprungTests
//
//  Pure-logic coverage for small value types:
//   - SearchPreferences — defaults + Codable round-trip
//
//  NOTE: SearchPreferences.load()/save() hardcodes UserDefaults.standard, so it
//  is NOT exercised here (would mutate the shared domain). Only the Codable
//  shape and defaults are tested directly.
//

import XCTest
@testable import Sprung

final class SmallModelsTests: XCTestCase {

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

}
