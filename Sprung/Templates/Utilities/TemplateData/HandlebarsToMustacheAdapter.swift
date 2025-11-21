//
//  HandlebarsToMustacheAdapter.swift
//  Sprung
//
//  Provides a best-effort translation layer so common Handlebars templates
//  (e.g. JSON Resume themes) can be rendered by GRMustache without requiring
//  a separate JavaScript runtime.
//
import Foundation
struct HandlebarsTranslationResult {
    let template: String
    let warnings: [String]
}
enum HandlebarsTranslator {
    static func translate(_ template: String) -> HandlebarsTranslationResult {
        var output = ""
        var warnings: [String] = []
        var stack: [SectionFrame] = []
        var currentIndex = template.startIndex
        let endIndex = template.endIndex
        while currentIndex < endIndex {
            guard let openRange = template.range(of: "{{", range: currentIndex..<endIndex) else {
                output.append(contentsOf: template[currentIndex..<endIndex])
                break
            }
            output.append(contentsOf: template[currentIndex..<openRange.lowerBound])
            let isTriple = template[openRange.upperBound..<endIndex].first == "{"
            let openingLength = isTriple ? 3 : 2
            let closingSequence = isTriple ? "}}}" : "}}"
            let exprStart = template.index(openRange.lowerBound, offsetBy: openingLength)
            guard let closeRange = template.range(of: closingSequence, range: exprStart..<endIndex) else {
                // Unterminated expression: append remainder and warn.
                warnings.append("Unterminated Handlebars expression near '\(template[openRange.lowerBound..<endIndex])'")
                output.append(contentsOf: template[openRange.lowerBound..<endIndex])
                currentIndex = endIndex
                break
            }
            let rawExpression = String(template[openRange.lowerBound..<closeRange.upperBound])
            let expressionContent = template[exprStart..<closeRange.lowerBound]
            let trimmed = expressionContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let translated: String
            if let replacement = translateExpression(
                trimmed,
                isTriple: isTriple,
                stack: &stack,
                warnings: &warnings
            ) {
                translated = replacement
            } else {
                translated = rawExpression
            }
            output.append(translated)
            currentIndex = closeRange.upperBound
        }
        if stack.isEmpty == false {
            for frame in stack.reversed() {
                warnings.append("Unclosed Handlebars section '{{#\(frame.name)}}'")
            }
        }
        let normalized = normalizeThisReferences(in: output)
        return HandlebarsTranslationResult(template: normalized, warnings: warnings)
    }
    private static func translateExpression(
        _ expression: String,
        isTriple: Bool,
        stack: inout [SectionFrame],
        warnings: inout [String]
    ) -> String? {
        guard expression.isEmpty == false else {
            return nil
        }
        if expression.hasPrefix("!--") {
            // Handlebars comments {{!-- ... --}} -> return as-is (triple braces never used here).
            return "{{\(expression)}}"
        }
        if expression.hasPrefix("!@") || expression.hasPrefix("! ") || expression == "!" {
            // Treat as standard Handlebars comment. Keep original content.
            return "{{\(expression)}}"
        }
        // Recognised helpers.
        if expression.hasPrefix("#if ") {
            return startConditionalSection(
                name: String(expression.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .ifSection,
                stack: &stack,
                warnings: &warnings
            )
        }
        if expression == "#if" {
            warnings.append("Encountered '{{#if}}' without a condition.")
            return "{{\(expression)}}"
        }
        if expression == "#resume" {
            stack.append(SectionFrame(kind: .noopSection, name: "resume", hasElse: false))
            return ""
        }
        if expression.hasPrefix("#unless ") {
            return startConditionalSection(
                name: String(expression.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .unlessSection,
                stack: &stack,
                warnings: &warnings
            )
        }
        if expression == "#unless" {
            warnings.append("Encountered '{{#unless}}' without a condition.")
            return "{{\(expression)}}"
        }
        if expression.hasPrefix("#each ") {
            return startConditionalSection(
                name: String(expression.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .eachSection,
                stack: &stack,
                warnings: &warnings
            )
        }
        if expression == "#each" {
            warnings.append("Encountered '{{#each}}' without a collection name.")
            return "{{\(expression)}}"
        }
        if expression == "else" {
            return handleElse(
                stack: &stack,
                warnings: &warnings
            )
        }
        if expression.hasPrefix("else ") {
            warnings.append("Unsupported Handlebars construct '{{\(expression)}}' (else-if is not supported).")
            return "{{\(expression)}}"
        }
        if expression.hasPrefix("/if") {
            return closeConditionalSection(
                kind: .ifSection,
                closingExpression: expression,
                stack: &stack,
                warnings: &warnings
            )
        }
        if expression.hasPrefix("/unless") {
            return closeConditionalSection(
                kind: .unlessSection,
                closingExpression: expression,
                stack: &stack,
                warnings: &warnings
            )
        }
        if expression.hasPrefix("/each") {
            return closeConditionalSection(
                kind: .eachSection,
                closingExpression: expression,
                stack: &stack,
                warnings: &warnings
            )
        }
        if expression == "/resume" {
            guard let frame = stack.popLast() else {
                warnings.append("Encountered '{{/resume}}' without an open section.")
                return ""
            }
            if frame.kind != .noopSection {
                warnings.append("Mismatched Handlebars section '{{/resume}}'; expected '{{#\(frame.name)}}'.")
            }
            return ""
        }
        if expression.contains("@index") {
            warnings.append("Handlebars '@index' helper is not supported; leaving token unchanged.")
            return nil
        }
        if expression.hasPrefix("lookup ") {
            warnings.append("Handlebars 'lookup' helper is not supported; leaving token unchanged.")
            return nil
        }
        if expression.hasPrefix("#with ") {
            warnings.append("Handlebars '#with' helper is not supported; leaving token unchanged.")
            return nil
        }
        // For triple braces, we keep the original string unchanged.
        if isTriple {
            return "{{{\(expression)}}}"
        }
        return "{{\(expression)}}"
    }
    private static func startConditionalSection(
        name: String,
        kind: SectionKind,
        stack: inout [SectionFrame],
        warnings: inout [String]
    ) -> String? {
        guard name.isEmpty == false else {
            warnings.append("Encountered conditional helper without a target expression.")
            return nil
        }
        // Reject Handlebars subexpressions (e.g. (eq foo bar)) which we cannot translate.
        if name.hasPrefix("(") {
            warnings.append("Unsupported Handlebars subexpression '\(name)' in conditional.")
            return "{{#\(name)}}"
        }
        let safeName = name
        let frame = SectionFrame(kind: kind, name: safeName, hasElse: false)
        stack.append(frame)
        switch kind {
        case .ifSection, .eachSection:
            return "{{#\(safeName)}}"
        case .unlessSection:
            return "{{^\(safeName)}}"
        case .noopSection:
            return ""
        }
    }
    private static func handleElse(
        stack: inout [SectionFrame],
        warnings: inout [String]
    ) -> String {
        guard var frame = stack.popLast() else {
            warnings.append("Encountered '{{else}}' without an open section.")
            return "{{else}}"
        }
        if frame.kind == .noopSection {
            warnings.append("Encountered '{{else}}' inside '{{#\(frame.name)}}', which is not supported.")
            stack.append(frame)
            return "{{else}}"
        }
        if frame.hasElse {
            warnings.append("Encountered multiple '{{else}}' blocks for '{{#\(frame.name)}}'.")
            stack.append(frame)
            return "{{else}}"
        }
        frame.hasElse = true
        stack.append(frame)
        switch frame.kind {
        case .ifSection, .eachSection:
            return "{{/\(frame.name)}}{{^\(frame.name)}}"
        case .unlessSection:
            return "{{/\(frame.name)}}{{#\(frame.name)}}"
        case .noopSection:
            return ""
        }
    }
    private static func closeConditionalSection(
        kind: SectionKind,
        closingExpression: String,
        stack: inout [SectionFrame],
        warnings: inout [String]
    ) -> String {
        guard let frame = stack.popLast() else {
            warnings.append("Encountered '{{\(closingExpression)}}' without an open section.")
            return "{{\(closingExpression)}}"
        }
        if frame.kind != kind {
            warnings.append("Mismatched Handlebars section '{{/\(closingExpression)}}'; expected '{{#\(frame.name)}}'.")
            return "{{\(closingExpression)}}"
        }
        switch frame.kind {
        case .ifSection, .eachSection, .unlessSection:
            return "{{/\(frame.name)}}"
        case .noopSection:
            return ""
        }
    }
    private static func normalizeThisReferences(in template: String) -> String {
        var result = template
        result = result.replacingOccurrences(
            of: #"\{\{\{\s*this\s*\}\}\}"#,
            with: "{{{.}}}",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\{\{\s*this\s*\}\}"#,
            with: "{{.}}",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\{\{\{\s*this\.([^\}]+?)\s*\}\}\}"#,
            with: "{{{$1}}}",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\{\{\s*this\.([^\}]+?)\s*\}\}"#,
            with: "{{$1}}",
            options: .regularExpression
        )
        return result
    }
    private struct SectionFrame {
        let kind: SectionKind
        let name: String
        var hasElse: Bool
    }
    private enum SectionKind {
        case ifSection
        case unlessSection
        case eachSection
        case noopSection
    }
}
