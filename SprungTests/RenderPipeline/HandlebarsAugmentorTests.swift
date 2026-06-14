//
//  HandlebarsAugmentorTests.swift
//  SprungTests
//
//  Phase 2 — HandlebarsContextAugmentor: pure [String: Any] -> [String: Any] enrichment.
//  No SwiftData needed. Pins the derived fields common JSON-Resume themes expect:
//  capitalName/capitalLabel, image/picture aliasing, contact-line pieces, top-level
//  section visibility flags (without clobbering pre-set flags), per-entry highlight/
//  keyword booleans, date splitting, and projectLine assembly.
//

import XCTest
@testable import Sprung

final class HandlebarsAugmentorTests: XCTestCase {

    private func augment(_ context: [String: Any]) -> [String: Any] {
        HandlebarsContextAugmentor.augment(context)
    }

    // MARK: - Basics: capitalization

    func testCapitalNameAndLabel() {
        let out = augment(["basics": ["name": "Ada Lovelace", "label": "Engineer"]])
        let basics = out["basics"] as? [String: Any]
        XCTAssertEqual(basics?["capitalName"] as? String, "ADA LOVELACE")
        XCTAssertEqual(basics?["capitalLabel"] as? String, "ENGINEER")
    }

    func testNoBasicsIsNoOp() {
        let out = augment(["work": [["name": "Acme"]]])
        XCTAssertNil(out["basics"])
    }

    // MARK: - Image / picture aliasing

    func testImageAliasesToPicture() {
        let out = augment(["basics": ["image": "data:image/png;base64,AAA"]])
        let basics = out["basics"] as? [String: Any]
        XCTAssertEqual(basics?["picture"] as? String, "data:image/png;base64,AAA",
                       "image must alias to picture")
        XCTAssertEqual(out["pictureBool"] as? Bool, true)
    }

    func testPictureAliasesToImage() {
        let out = augment(["basics": ["picture": "data:image/png;base64,BBB"]])
        let basics = out["basics"] as? [String: Any]
        XCTAssertEqual(basics?["image"] as? String, "data:image/png;base64,BBB")
    }

    func testPictureBoolFalseWhenAbsent() {
        let out = augment(["basics": ["name": "Ada"]])
        XCTAssertEqual(out["pictureBool"] as? Bool, false)
    }

    // MARK: - Contact-line pieces

    func testContactPiecesOrderLocationPhoneEmailWebsite() {
        let basics: [String: Any] = [
            "location": ["city": "London", "region": "England", "countryCode": "GB"],
            "phone": "(555) 010-0101",
            "email": "ada@example.com",
            "website": "example.com"
        ]
        let out = augment(["basics": basics])
        let pieces = out["contactLinePieces"] as? [String]
        XCTAssertEqual(pieces, ["London, England, GB", "(555) 010-0101", "ada@example.com", "example.com"])
    }

    func testContactPiecesFallBackToURLWhenNoWebsite() {
        let out = augment(["basics": ["email": "a@b.com", "url": "site.dev"]])
        let pieces = out["contactLinePieces"] as? [String]
        XCTAssertEqual(pieces, ["a@b.com", "site.dev"])
    }

    func testContactBooleanFlags() {
        let out = augment(["basics": [
            "email": "a@b.com", "phone": "123", "website": "w",
            "profiles": [["network": "GitHub"]], "summary": "hi",
            "location": ["city": "X"]
        ]])
        XCTAssertEqual(out["emailBool"] as? Bool, true)
        XCTAssertEqual(out["phoneBool"] as? Bool, true)
        XCTAssertEqual(out["websiteBool"] as? Bool, true)
        XCTAssertEqual(out["profilesBool"] as? Bool, true)
        XCTAssertEqual(out["aboutBool"] as? Bool, true)
        XCTAssertEqual(out["locationBool"] as? Bool, true)
    }

    // MARK: - Top-level section visibility flags

    func testSectionFlagsFilledFromPresence() {
        let out = augment([
            "basics": ["name": "Ada"],
            "work": [["name": "Acme"]],
            "skills": [[String: Any]]() // empty array ⇒ false
        ])
        XCTAssertEqual(out["workBool"] as? Bool, true)
        XCTAssertEqual(out["skillsBool"] as? Bool, false)
        XCTAssertEqual(out["educationBool"] as? Bool, false, "absent section ⇒ false")
    }

    func testPreSetSectionFlagNotClobbered() {
        // ResumeTemplateDataBuilder may have already hidden a section (flag == false)
        // even though data is present. The augmentor must NOT recompute it back to true.
        let out = augment([
            "work": [["name": "Acme"]],
            "workBool": false
        ])
        XCTAssertEqual(out["workBool"] as? Bool, false,
                       "augmentor must not clobber an already-set visibility flag")
    }

    // MARK: - Work entry enrichment

    func testWorkHighlightsBooleanAndDates() {
        let out = augment(["work": [[
            "position": "Engineer",
            "highlights": ["Did a thing"],
            "startDate": "2020-03",
            "endDate": ""
        ]]])
        let work = out["work"] as? [[String: Any]]
        let item = work?.first
        XCTAssertEqual(item?["workHighlights"] as? Bool, true)
        XCTAssertEqual(item?["startDateMonth"] as? String, "Mar ")
        XCTAssertEqual(item?["startDateYear"] as? String, "2020")
        // empty endDate ⇒ "Present"
        XCTAssertEqual(item?["endDateYear"] as? String, "Present")
    }

    func testWorkHighlightsFalseWhenEmpty() {
        let out = augment(["work": [["position": "Eng", "highlights": [String]()]]])
        let item = (out["work"] as? [[String: Any]])?.first
        XCTAssertEqual(item?["workHighlights"] as? Bool, false)
    }

    // MARK: - Skills / interests keyword flags

    func testSkillsKeywordsBool() {
        let out = augment(["skills": [
            ["name": "Swift", "keywords": ["async", "actors"]],
            ["name": "Empty", "keywords": [String]()]
        ]])
        let skills = out["skills"] as? [[String: Any]]
        XCTAssertEqual(skills?[0]["keywordsBool"] as? Bool, true)
        XCTAssertEqual(skills?[1]["keywordsBool"] as? Bool, false)
    }

    // MARK: - Education enrichment

    func testEducationFlags() {
        let out = augment(["education": [[
            "institution": "MIT",
            "gpa": "4.0",
            "courses": ["Algorithms"],
            "startDate": "2016-09",
            "endDate": "2020-06"
        ]]])
        let item = (out["education"] as? [[String: Any]])?.first
        XCTAssertEqual(item?["gpaBool"] as? Bool, true)
        XCTAssertEqual(item?["educationCourses"] as? Bool, true)
        XCTAssertEqual(item?["startDateYear"] as? String, "2016")
        XCTAssertEqual(item?["endDateYear"] as? String, "2020")
    }

    // MARK: - Projects projectLine

    func testProjectLineCombinesNameAndDescription() {
        let out = augment(["projects": [["name": "Sprung", "description": "Resume tool"]]])
        let item = (out["projects"] as? [[String: Any]])?.first
        XCTAssertEqual(item?["projectLine"] as? String, "Sprung: Resume tool")
        XCTAssertEqual(item?["projectKeywords"] as? Bool, false)
    }

    func testProjectLineNameOnly() {
        let out = augment(["projects": [["name": "Sprung"]]])
        let item = (out["projects"] as? [[String: Any]])?.first
        XCTAssertEqual(item?["projectLine"] as? String, "Sprung")
    }

    // MARK: - Awards day/month/year splitting

    func testAwardDateSplitting() {
        let out = augment(["awards": [["title": "Prize", "date": "2021-07-15"]]])
        let item = (out["awards"] as? [[String: Any]])?.first
        XCTAssertEqual(item?["day"] as? String, "15")
        XCTAssertEqual(item?["month"] as? String, "Jul")
        XCTAssertEqual(item?["year"] as? String, "2021")
    }

    // MARK: - Languages / references key aliasing

    func testLanguageNameAliasesToLanguage() {
        let out = augment(["languages": [["name": "French", "fluency": "Native"]]])
        let item = (out["languages"] as? [[String: Any]])?.first
        XCTAssertEqual(item?["language"] as? String, "French", "name aliases to language when language absent")
    }

    func testReferenceTextAliasesToReference() {
        let out = augment(["references": [["text": "Great engineer."]]])
        let item = (out["references"] as? [[String: Any]])?.first
        XCTAssertEqual(item?["reference"] as? String, "Great engineer.")
    }

    // MARK: - Location state/region cross-fill

    func testLocationStateRegionCrossFill() {
        let out = augment(["basics": ["location": ["state": "Texas"]]])
        let location = (out["basics"] as? [String: Any])?["location"] as? [String: Any]
        XCTAssertEqual(location?["region"] as? String, "Texas", "state cross-fills region")
    }
}
