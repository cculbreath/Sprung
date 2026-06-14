//
//  ExperienceCodecTests.swift
//  SprungTests
//
//  Pure-logic coverage for ExperienceDefaultsDecoder + ExperienceSectionCodec:
//  array-section decode, missing-section fallback (disabled + emptied), wrong-type
//  fallback, custom-field flattening (string and array values), and a
//  decode -> re-encode round-trip through a section codec.
//
//  Drafts are plain Codable/Equatable value types with zero-arg inits, so no
//  SwiftData model is touched.
//

import XCTest
import SwiftyJSON
@testable import Sprung

final class ExperienceCodecTests: XCTestCase {

    // MARK: - ExperienceDefaultsDecoder: array sections

    func testDecodeWorkSectionEnablesAndPopulates() {
        let json = JSON([
            "work": [
                [
                    "name": "Acme",
                    "position": "Engineer",
                    "highlights": ["Shipped X", "Built Y"]
                ]
            ]
        ])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        XCTAssertTrue(draft.isWorkEnabled, "a non-empty work array must enable the section")
        XCTAssertEqual(draft.work.count, 1)
        XCTAssertEqual(draft.work.first?.name, "Acme")
        XCTAssertEqual(draft.work.first?.position, "Engineer")
        XCTAssertEqual(draft.work.first?.highlights.map(\.text), ["Shipped X", "Built Y"])
    }

    func testDecodeTrimsWhitespaceInValues() {
        let json = JSON(["work": [["name": "  Acme  ", "position": " Eng "]]])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        XCTAssertEqual(draft.work.first?.name, "Acme", "decoded string fields are trimmed")
        XCTAssertEqual(draft.work.first?.position, "Eng")
    }

    func testMissingSectionDisablesAndEmpties() {
        // No "education" key present -> section decoded as disabled + empty.
        let json = JSON(["work": [["name": "Acme"]]])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        XCTAssertFalse(draft.isEducationEnabled, "absent section must be disabled")
        XCTAssertTrue(draft.education.isEmpty)
    }

    func testEmptyArraySectionIsDisabled() {
        let json = JSON(["languages": []])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        XCTAssertFalse(draft.isLanguagesEnabled, "an empty array enables nothing")
        XCTAssertTrue(draft.languages.isEmpty)
    }

    // MARK: - Custom-field flattening

    func testCustomFieldStringValueFlattens() {
        let json = JSON(["custom": ["objective": "Land a great role"]])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        XCTAssertTrue(draft.isCustomEnabled)
        let field = draft.customFields.first { $0.key == "objective" }
        XCTAssertEqual(field?.values, ["Land a great role"])
    }

    func testCustomFieldArrayValueFlattens() {
        let json = JSON(["custom": ["jobTitles": ["Engineer", "Architect"]]])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        let field = draft.customFields.first { $0.key == "jobTitles" }
        XCTAssertEqual(field?.values, ["Engineer", "Architect"])
    }

    func testCustomFieldEmptyValuesAreDropped() {
        // A key whose value is an empty string contributes no values -> field dropped.
        let json = JSON(["custom": ["empty": "   ", "kept": "value"]])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        XCTAssertNil(draft.customFields.first { $0.key == "empty" },
                     "a whitespace-only custom value must be dropped")
        XCTAssertNotNil(draft.customFields.first { $0.key == "kept" })
    }

    func testNoCustomSectionLeavesCustomDisabled() {
        let draft = ExperienceDefaultsDecoder.draft(from: JSON(["work": [["name": "A"]]]))
        XCTAssertFalse(draft.isCustomEnabled)
        XCTAssertTrue(draft.customFields.isEmpty)
    }

    // MARK: - Codec wrong-type fallback

    func testCodecWrongTypeFallsBackToDisabled() {
        // A section codec given a non-array JSON disables + empties the section.
        let workCodec = ExperienceSectionCodecs.all.first { $0.key == .work }
        let codec = try? XCTUnwrap(workCodec)
        var draft = ExperienceDefaultsDraft()
        draft.isWorkEnabled = true
        draft.work = [WorkExperienceDraft()]
        codec?.decodeSection(from: JSON("a string, not an array"), into: &draft)
        XCTAssertFalse(draft.isWorkEnabled, "non-array section must disable")
        XCTAssertTrue(draft.work.isEmpty)
    }

    func testCodecNilSectionDisables() {
        let codec = ExperienceSectionCodecs.all.first { $0.key == .languages }
        var draft = ExperienceDefaultsDraft()
        draft.isLanguagesEnabled = true
        draft.languages = [LanguageExperienceDraft()]
        codec?.decodeSection(from: nil, into: &draft)
        XCTAssertFalse(draft.isLanguagesEnabled)
        XCTAssertTrue(draft.languages.isEmpty)
    }

    // MARK: - encodeSection

    func testEncodeSectionSkipsWhenDisabled() {
        let codec = ExperienceSectionCodecs.all.first { $0.key == .work }
        var draft = ExperienceDefaultsDraft()
        draft.isWorkEnabled = false  // disabled -> encode yields nil even with items
        draft.work = [{ var w = WorkExperienceDraft(); w.name = "Acme"; return w }()]
        XCTAssertNil(codec?.encodeSection(from: draft),
                     "a disabled section must not encode")
    }

    func testEncodeSectionDropsEmptyItems() {
        let codec = ExperienceSectionCodecs.all.first { $0.key == .work }
        var draft = ExperienceDefaultsDraft()
        draft.isWorkEnabled = true
        draft.work = [WorkExperienceDraft()]  // all-empty item -> filtered out
        XCTAssertNil(codec?.encodeSection(from: draft),
                     "an entirely-empty entry encodes to nothing -> section is nil")
    }

    // MARK: - Decode -> re-encode round trip

    func testDecodeThenEncodePreservesWork() {
        let json = JSON([
            "work": [["name": "Acme", "position": "Engineer", "highlights": ["Did a thing"]]]
        ])
        let draft = ExperienceDefaultsDecoder.draft(from: json)
        let codec = ExperienceSectionCodecs.all.first { $0.key == .work }
        let encoded = codec?.encodeSection(from: draft)
        let first = try? XCTUnwrap(encoded?.first)
        XCTAssertEqual(first?["name"] as? String, "Acme")
        XCTAssertEqual(first?["position"] as? String, "Engineer")
        XCTAssertEqual(first?["highlights"] as? [String], ["Did a thing"])
    }
}
