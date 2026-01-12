//
//  BibTeXParser.swift
//  Sprung
//
//  Parser for BibTeX (.bib) files to extract publication entries.
//  Converts BibTeX entries to PublicationCard models for onboarding.
//

import Foundation

/// Parser for BibTeX formatted bibliography files
struct BibTeXParser {

    // MARK: - Parsed Entry

    /// A parsed BibTeX entry with all fields
    struct ParsedEntry {
        let key: String           // e.g., "smith2023"
        let type: String          // e.g., "article", "inproceedings", "book"
        var fields: [String: String] = [:]

        // Common field accessors
        var title: String? { fields["title"] }
        var author: String? { fields["author"] }
        var year: String? { fields["year"] }
        var journal: String? { fields["journal"] }
        var booktitle: String? { fields["booktitle"] }
        var publisher: String? { fields["publisher"] }
        var doi: String? { fields["doi"] }
        var url: String? { fields["url"] }
        var abstract: String? { fields["abstract"] }
        var pages: String? { fields["pages"] }
        var volume: String? { fields["volume"] }
        var number: String? { fields["number"] }

        /// Get the publisher name from various possible fields
        var publisherName: String {
            // Try journal first (for articles), then booktitle (for conference papers), then publisher
            journal ?? booktitle ?? publisher ?? ""
        }

        /// Parse author field into individual author names
        var authorList: [String] {
            guard let author = author else { return [] }
            // BibTeX authors are separated by "and"
            return author
                .components(separatedBy: " and ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    // MARK: - Parsing

    /// Parse BibTeX content into an array of entries
    static func parse(_ content: String) -> [ParsedEntry] {
        var entries: [ParsedEntry] = []

        // Regular expression to match BibTeX entries
        // Matches: @type{key, ... }
        let entryPattern = #"@(\w+)\s*\{\s*([^,\s]+)\s*,([^@]*?)(?=\n\s*@|\n*$)"#

        guard let regex = try? NSRegularExpression(pattern: entryPattern, options: [.dotMatchesLineSeparators]) else {
            Logger.error("BibTeXParser: Failed to create regex", category: .ai)
            return entries
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 4,
                  let typeRange = Range(match.range(at: 1), in: content),
                  let keyRange = Range(match.range(at: 2), in: content),
                  let fieldsRange = Range(match.range(at: 3), in: content) else {
                continue
            }

            let type = String(content[typeRange]).lowercased()
            let key = String(content[keyRange])
            let fieldsContent = String(content[fieldsRange])

            // Skip comment and string entries
            guard type != "comment" && type != "string" && type != "preamble" else {
                continue
            }

            var entry = ParsedEntry(key: key, type: type)
            entry.fields = parseFields(fieldsContent)
            entries.append(entry)
        }

        return entries
    }

    /// Parse the fields section of a BibTeX entry
    private static func parseFields(_ content: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Pattern to match field = {value} or field = "value" or field = number
        let fieldPattern = #"(\w+)\s*=\s*(?:\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}|"([^"]*)"|(\d+))"#

        guard let regex = try? NSRegularExpression(pattern: fieldPattern, options: [.dotMatchesLineSeparators]) else {
            return fields
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 2,
                  let keyRange = Range(match.range(at: 1), in: content) else {
                continue
            }

            let key = String(content[keyRange]).lowercased()

            // Try to get value from braces, quotes, or number
            var value: String?
            if match.range(at: 2).location != NSNotFound,
               let valueRange = Range(match.range(at: 2), in: content) {
                value = String(content[valueRange])
            } else if match.range(at: 3).location != NSNotFound,
                      let valueRange = Range(match.range(at: 3), in: content) {
                value = String(content[valueRange])
            } else if match.range(at: 4).location != NSNotFound,
                      let valueRange = Range(match.range(at: 4), in: content) {
                value = String(content[valueRange])
            }

            if let value = value {
                // Clean up LaTeX commands and normalize whitespace
                fields[key] = cleanLaTeX(value)
            }
        }

        return fields
    }

    /// Clean up LaTeX formatting from a string
    private static func cleanLaTeX(_ text: String) -> String {
        var result = text

        // Remove common LaTeX commands
        let commands: [(pattern: String, replacement: String)] = [
            (#"\\textbf\{([^}]*)\}"#, "$1"),
            (#"\\textit\{([^}]*)\}"#, "$1"),
            (#"\\emph\{([^}]*)\}"#, "$1"),
            (#"\\textrm\{([^}]*)\}"#, "$1"),
            (#"\\texttt\{([^}]*)\}"#, "$1"),
            (#"\\url\{([^}]*)\}"#, "$1"),
            (#"\\href\{[^}]*\}\{([^}]*)\}"#, "$1"),
            (#"\\\\"#, " "),
            (#"\\&"#, "&"),
            (#"\\%"#, "%"),
            ("\\\\#", "#"),  // Match \# in LaTeX
            (#"\\~"#, "~"),
            (#"\\{"#, "{"),
            (#"\\}"#, "}"),
        ]

        for (pattern, replacement) in commands {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        // Normalize whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // MARK: - Conversion to PublicationCard

    /// Convert a parsed BibTeX entry to a PublicationCard
    static func toPublicationCard(_ entry: ParsedEntry) -> PublicationCard {
        PublicationCard(
            id: UUID().uuidString,
            name: entry.title ?? "",
            publisher: entry.publisherName,
            releaseDate: entry.year ?? "",
            url: entry.url ?? "",
            summary: entry.abstract ?? "",
            sourceType: .bibtex,
            bibtexKey: entry.key,
            bibtexType: entry.type,
            authors: entry.authorList,
            doi: entry.doi
        )
    }

    /// Parse BibTeX content and convert to PublicationCards
    static func parseToPublicationCards(_ content: String) -> [PublicationCard] {
        let entries = parse(content)
        return entries.map { toPublicationCard($0) }
    }

    /// Parse a BibTeX file at the given URL and convert to PublicationCards
    static func parseFile(at url: URL) throws -> [PublicationCard] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseToPublicationCards(content)
    }
}
