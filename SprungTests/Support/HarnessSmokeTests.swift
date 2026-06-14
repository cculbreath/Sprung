//
//  HarnessSmokeTests.swift
//  SprungTests
//
//  Proves the Phase 0 test harness itself works: an in-memory container boots from the
//  canonical schema, models round-trip through it, and the isolated UserDefaults suite
//  stays off `UserDefaults.standard`. If any of these fail, every later phase is suspect.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class HarnessSmokeTests: InMemoryStoreCase {

    func testInMemoryContainerBootsFromCanonicalSchema() throws {
        XCTAssertNotNil(container, "in-memory container must build from SprungSchema.schema")
        // A fresh container holds nothing.
        XCTAssertEqual(try fetchAll(ApplicantProfile.self).count, 0)
    }

    func testModelInsertAndFetchRoundTrips() throws {
        let profile = insert(Fixtures.makeApplicantProfile(name: "Grace Hopper"))
        saveContext()

        let fetched = try fetchAll(ApplicantProfile.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Grace Hopper")
        XCTAssertEqual(fetched.first?.persistentModelID, profile.persistentModelID)
    }

    func testEachTestGetsAFreshContainer() throws {
        // This test must see an empty store even though `testModelInsertAndFetchRoundTrips`
        // inserts a profile — setUp rebuilds the container per method.
        XCTAssertEqual(try fetchAll(ApplicantProfile.self).count, 0,
                       "containers must not leak state across test methods")
    }

    func testExperienceDefaultsFixtureIsEmptyButValid() throws {
        let defaults = insert(Fixtures.makeEmptyExperienceDefaults(seedCreated: true))
        saveContext()
        let fetched = try fetchAll(ExperienceDefaults.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertTrue(fetched.first?.seedCreated ?? false)
        XCTAssertTrue(fetched.first?.work.isEmpty ?? false)
    }

    func testTestDefaultsIsolatesFromStandard() {
        let key = "harness.smoke.key"
        let defaults = TestDefaults()
        defaults.store.set("scoped-value", forKey: key)

        XCTAssertEqual(defaults.store.string(forKey: key), "scoped-value")
        XCTAssertNil(UserDefaults.standard.string(forKey: key),
                     "test suite must never write into UserDefaults.standard")

        defaults.reset()
        XCTAssertNil(defaults.store.string(forKey: key), "reset() must wipe the suite")
    }
}
