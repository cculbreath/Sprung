//
//  EditorFontScaleTests.swift
//  SprungTests
//
//  Pure clamp/normalize logic behind the editor font-size menu commands.
//  Exercises the dependency-free halves only — the UserDefaults-backed
//  `current`/`adjust`/`reset` are thin wrappers over these.
//

import XCTest
@testable import Sprung

final class EditorFontScaleTests: XCTestCase {

    // MARK: - normalized

    func testNormalizedTreatsAbsentAsDefault() {
        XCTAssertEqual(EditorFontScale.normalized(nil), EditorFontScale.defaultScale)
    }

    func testNormalizedTreatsZeroAsDefault() {
        // A UserDefaults double is 0 when the key was never written.
        XCTAssertEqual(EditorFontScale.normalized(0), EditorFontScale.defaultScale)
    }

    func testNormalizedPassesThroughRealValue() {
        XCTAssertEqual(EditorFontScale.normalized(1.3), 1.3)
    }

    // MARK: - clamped

    func testClampedHoldsWithinRange() {
        XCTAssertEqual(EditorFontScale.clamped(1.0), 1.0)
        XCTAssertEqual(EditorFontScale.clamped(EditorFontScale.minScale), EditorFontScale.minScale)
        XCTAssertEqual(EditorFontScale.clamped(EditorFontScale.maxScale), EditorFontScale.maxScale)
    }

    func testClampedFloorsBelowMin() {
        XCTAssertEqual(EditorFontScale.clamped(0.1), EditorFontScale.minScale)
    }

    func testClampedCeilingsAboveMax() {
        XCTAssertEqual(EditorFontScale.clamped(5.0), EditorFontScale.maxScale)
    }

    // MARK: - stepping (the menu-command arithmetic)

    func testRepeatedIncreaseSaturatesAtMax() {
        var scale = EditorFontScale.defaultScale
        for _ in 0..<100 {
            scale = EditorFontScale.clamped(scale + EditorFontScale.step)
        }
        XCTAssertEqual(scale, EditorFontScale.maxScale)
    }

    func testRepeatedDecreaseSaturatesAtMin() {
        var scale = EditorFontScale.defaultScale
        for _ in 0..<100 {
            scale = EditorFontScale.clamped(scale - EditorFontScale.step)
        }
        XCTAssertEqual(scale, EditorFontScale.minScale)
    }

    func testKeysAreDistinct() {
        // The two panes must persist independently.
        XCTAssertNotEqual(EditorFontScale.jobListKey, EditorFontScale.resumeEditorKey)
    }
}
