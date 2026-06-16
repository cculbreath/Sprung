//
//  YearOnlyFilterTests.swift
//  SprungTests
//
//  Phase 5 (PDF / D-03) — the real `yearOnly` GRMustache filter replacing the
//  former strip-hack in NativePDFGenerator. Two halves:
//   1. HandlebarsTranslator rewrites the Handlebars space-call `{{yearOnly x}}`
//      into GRMustache paren-call `{{yearOnly(x)}}` (pure String→String).
//   2. The registered filter extracts the 4-digit year (exercised via a render).
//

import XCTest
import Mustache
@testable import Sprung

final class YearOnlyFilterTests: XCTestCase {

    // MARK: - Adapter: space-call -> paren-call translation

    func testTranslatesThisPrefixedYearOnly() {
        let out = HandlebarsTranslator.translate("{{yearOnly this.start}}").template
        XCTAssertEqual(out, "{{yearOnly(start)}}")
    }

    func testTranslatesBareArgYearOnly() {
        let out = HandlebarsTranslator.translate("{{yearOnly end}}").template
        XCTAssertEqual(out, "{{yearOnly(end)}}")
    }

    func testTranslatesTripleBraceYearOnly() {
        let out = HandlebarsTranslator.translate("{{{yearOnly this.start}}}").template
        XCTAssertEqual(out, "{{{yearOnly(start)}}}")
    }

    func testDoesNotRewriteNonWhitelistedSpaceCall() {
        // Only `yearOnly` is in the inline-filter whitelist; other space-call
        // expressions must pass through unchanged (no behavior change).
        let out = HandlebarsTranslator.translate("{{uppercase title}}").template
        XCTAssertEqual(out, "{{uppercase title}}")
    }

    // MARK: - Filter: 4-digit year extraction (via render)

    private func render(_ template: String, _ data: [String: Any]) throws -> String {
        let mustache = try Template(string: template)
        TemplateFilters.register(on: mustache)
        return try mustache.render(data)
    }

    func testExtractsYearFromFullDate() throws {
        XCTAssertEqual(try render("{{yearOnly(d)}}", ["d": "2021-06-15"]), "2021")
    }

    func testExtractsYearFromYearMonth() throws {
        XCTAssertEqual(try render("{{yearOnly(d)}}", ["d": "2019-03"]), "2019")
    }

    func testYearOnlyPassesThroughBareYear() throws {
        XCTAssertEqual(try render("{{yearOnly(d)}}", ["d": "2018"]), "2018")
    }

    func testYearOnlyKeepsPresent() throws {
        XCTAssertEqual(try render("{{yearOnly(d)}}", ["d": "present"]), "Present")
    }

    func testYearOnlyPassesThroughUnparseable() throws {
        XCTAssertEqual(try render("{{yearOnly(d)}}", ["d": "sometime"]), "sometime")
    }

    func testTranslatedTemplateRendersYear() throws {
        // End-to-end: the translated paren-call resolves the bare key against the
        // current context and the filter extracts the year.
        let translated = HandlebarsTranslator.translate("{{yearOnly this.start}}").template
        XCTAssertEqual(try render(translated, ["start": "2020-09-01"]), "2020")
    }
}
