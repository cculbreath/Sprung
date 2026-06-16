//
//  ScriptJSONExtractorTests.swift
//  SprungTests
//
//  Phase 5 — pure JSON-from-HTML extraction shared by the Indeed (JSON-LD
//  <script>) and Apple (inline `JSON.parse("…")`) scrapers.
//

import XCTest
@testable import Sprung

final class ScriptJSONExtractorTests: XCTestCase {

    // MARK: - objects(in:cssSelector:) + firstJSONLD (Indeed path)

    func testFindsJobPostingInLdJsonScript() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"JobPosting","title":"Engineer","hiringOrganization":{"name":"Acme"}}
        </script>
        </head></html>
        """
        let objects = ScriptJSONExtractor.objects(in: html, cssSelector: "script[type=application/ld+json]")
        let posting = ScriptJSONExtractor.firstJSONLD(ofType: "JobPosting", among: objects)
        XCTAssertEqual(posting?["title"] as? String, "Engineer")
        XCTAssertEqual((posting?["hiringOrganization"] as? [String: Any])?["name"] as? String, "Acme")
    }

    func testStripsHTMLCommentWrapper() {
        // Indeed sometimes wraps the JSON-LD payload in an HTML comment.
        let html = """
        <script type="application/ld+json"><!--
        {"@type":"JobPosting","title":"Wrapped"}
        --></script>
        """
        let withStrip = ScriptJSONExtractor.objects(in: html, cssSelector: "script[type=application/ld+json]", stripHTMLComments: true)
        XCTAssertNotNil(ScriptJSONExtractor.firstJSONLD(ofType: "JobPosting", among: withStrip))

        let withoutStrip = ScriptJSONExtractor.objects(in: html, cssSelector: "script[type=application/ld+json]", stripHTMLComments: false)
        XCTAssertNil(ScriptJSONExtractor.firstJSONLD(ofType: "JobPosting", among: withoutStrip),
                     "comment-wrapped JSON should not decode without stripping")
    }

    func testFindsJobPostingInsideArray() {
        let html = """
        <script type="application/ld+json">
        [{"@type":"Organization","name":"Acme"},{"@type":"JobPosting","title":"In Array"}]
        </script>
        """
        let objects = ScriptJSONExtractor.objects(in: html, cssSelector: "script[type=application/ld+json]")
        XCTAssertEqual(ScriptJSONExtractor.firstJSONLD(ofType: "JobPosting", among: objects)?["title"] as? String, "In Array")
    }

    func testMatchesTypeArray() {
        let html = """
        <script type="application/ld+json">
        {"@type":["WebPage","JobPosting"],"title":"Multi"}
        </script>
        """
        let objects = ScriptJSONExtractor.objects(in: html, cssSelector: "script[type=application/ld+json]")
        XCTAssertEqual(ScriptJSONExtractor.firstJSONLD(ofType: "JobPosting", among: objects)?["title"] as? String, "Multi")
    }

    func testNoJobPostingReturnsNil() {
        let html = """
        <script type="application/ld+json">{"@type":"Organization","name":"Acme"}</script>
        """
        let objects = ScriptJSONExtractor.objects(in: html, cssSelector: "script[type=application/ld+json]")
        XCTAssertNil(ScriptJSONExtractor.firstJSONLD(ofType: "JobPosting", among: objects))
    }

    func testNoMatchingScriptReturnsEmpty() {
        XCTAssertTrue(ScriptJSONExtractor.objects(in: "<html><body>no scripts</body></html>",
                                                  cssSelector: "script[type=application/ld+json]").isEmpty)
    }

    // MARK: - object(in:capturePattern:unescape:) (Apple path)

    private let appleCapture = "window\\.__staticRouterHydrationData = JSON\\.parse\\(\"(.*)\"\\);"

    func testExtractsEscapedInlineJSON() {
        // On-page text: window.__staticRouterHydrationData = JSON.parse("{\"loaderData\":{\"x\":1}}");
        let html = "<script>window.__staticRouterHydrationData = JSON.parse(\"{\\\"loaderData\\\":{\\\"x\\\":1}}\");</script>"
        let object = ScriptJSONExtractor.object(in: html, capturePattern: appleCapture, unescape: true)
        XCTAssertEqual((object?["loaderData"] as? [String: Any])?["x"] as? Int, 1)
    }

    func testInlineJSONNoMatchReturnsNil() {
        let html = "<script>var other = 1;</script>"
        XCTAssertNil(ScriptJSONExtractor.object(in: html, capturePattern: appleCapture, unescape: true))
    }

    func testInlineJSONMalformedReturnsNil() {
        // Captured but not valid JSON after unescaping.
        let html = "<script>window.__staticRouterHydrationData = JSON.parse(\"not json\");</script>"
        XCTAssertNil(ScriptJSONExtractor.object(in: html, capturePattern: appleCapture, unescape: true))
    }
}
