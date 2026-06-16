//
//  ScriptJSONExtractor.swift
//  Sprung
//
//  Pure helpers for pulling embedded JSON out of scraped job-posting HTML.
//  Two extraction modes cover the static-HTML scrapers:
//    - `objects(in:cssSelector:)`   — Indeed's `<script type=application/ld+json>` blocks
//    - `object(in:capturePattern:)` — Apple's inline `window.__… = JSON.parse("…")` assignment
//  plus a site-agnostic JSON-LD `@type` discriminator. (LinkedIn extracts via a
//  live WKWebView, not static HTML, so it does not use this helper.)
//

import Foundation
import SwiftSoup

enum ScriptJSONExtractor {

    /// Decode every `<script>` matching `cssSelector` and return the parsed
    /// top-level JSON values (objects or arrays), in document order. When
    /// `stripHTMLComments` is true, `<!--`/`-->` wrappers are removed before
    /// decoding (Indeed sometimes wraps its JSON-LD in comments).
    static func objects(in html: String, cssSelector: String, stripHTMLComments: Bool = false) -> [Any] {
        guard let doc = try? SwiftSoup.parse(html),
              let tags = try? doc.select(cssSelector) else {
            return []
        }
        var results: [Any] = []
        for tag in tags.array() {
            guard var content = try? tag.html() else { continue }
            if stripHTMLComments {
                content = content
                    .replacingOccurrences(of: "<!--", with: "")
                    .replacingOccurrences(of: "-->", with: "")
            }
            guard let data = content.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: []) else {
                continue
            }
            results.append(obj)
        }
        return results
    }

    /// Capture an inline-assignment JSON string via `capturePattern` (the JSON
    /// must be in capture group 1), optionally unescape `\"`/`\\`, then decode to
    /// a top-level object.
    static func object(in html: String, capturePattern: String, unescape: Bool = false) -> [String: Any]? {
        guard let regex = try? NSRegularExpression(pattern: capturePattern, options: []),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        var captured = String(html[range])
        if unescape {
            captured = captured
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        guard let data = captured.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    /// Find the first JSON-LD object whose `@type` matches `type`
    /// (case-insensitive) among decoded top-level values; descends into arrays.
    /// `@type` may be a string or an array of strings.
    static func firstJSONLD(ofType type: String, among objects: [Any]) -> [String: Any]? {
        let target = type.lowercased()
        func matches(_ dict: [String: Any]) -> Bool {
            if let single = dict["@type"] as? String {
                return single.lowercased() == target
            }
            if let many = dict["@type"] as? [String] {
                return many.contains { $0.lowercased() == target }
            }
            return false
        }
        func search(_ value: Any) -> [String: Any]? {
            if let dict = value as? [String: Any] {
                return matches(dict) ? dict : nil
            }
            if let array = value as? [Any] {
                for element in array {
                    if let found = search(element) { return found }
                }
            }
            return nil
        }
        for object in objects {
            if let found = search(object) { return found }
        }
        return nil
    }
}
