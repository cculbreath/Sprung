//
//  TemplateTextFilters.swift
//  Sprung
//

import Foundation

struct TemplateTextFilters {
    static let reference: [TextFilterInfo] = [
        TextFilterInfo(
            name: "center",
            signature: "center(text, width)",
            description: "Centers the provided text within the given width.",
            snippet: "{{{ center(value, 72) }}}"
        ),
        TextFilterInfo(
            name: "wrap",
            signature: "wrap(text, width, leftMargin, rightMargin)",
            description: "Wraps text to the specified width with optional margins.",
            snippet: "{{{ wrap(text, 72, 4, 4) }}}"
        ),
        TextFilterInfo(
            name: "sectionLine",
            signature: "sectionLine(label, width)",
            description: "Builds a decorative section header line.",
            snippet: "{{{ sectionLine(section-labels.summary, 72) }}}"
        ),
        TextFilterInfo(
            name: "join",
            signature: "join(array, separator)",
            description: "Joins array elements into a single string using the separator.",
            snippet: "{{ join(skills, \", \") }}"
        ),
        TextFilterInfo(
            name: "contactLine",
            signature: "center(join(basics.contactLinePieces, separator), width)",
            description: "Centers a dot-separated contact line using the precomputed pieces array (location, phone, email, url).",
            snippet: "{{{ center(join(basics.contactLinePieces, \" · \"), 80) }}}"
        ),
        TextFilterInfo(
            name: "htmlDecode",
            signature: "htmlDecode(text)",
            description: "Decodes HTML entities without stripping tags.",
            snippet: "{{{ htmlDecode(position) }}}"
        ),
        TextFilterInfo(
            name: "projectLine",
            signature: "projects[].projectLine",
            description: "Precomputed \"Name: Description\" string for each project entry. Useful for wrapping without custom separators.",
            snippet: "{{{ wrap(projectLine, 80, 0, 0) }}}"
        ),
        TextFilterInfo(
            name: "concatPair",
            signature: "concatPair(first, second, separator?)",
            description: "Concatenates two values with an optional separator value pulled from context (defaults to a single space).",
            snippet: "{{ concatPair(name, description) }}"
        ),
        TextFilterInfo(
            name: "bulletList",
            signature: "bulletList(array, width, indent, bullet, valueKey)",
            description: "Formats an array as bullet points. `valueKey` is optional for dictionary arrays.",
            snippet: "{{{ bulletList(highlights, 72, 2, \"•\") }}}"
        ),
        TextFilterInfo(
            name: "formatDate",
            signature: "formatDate(date, outputFormat, inputFormat)",
            description: "Formats dates (default input patterns include ISO and yyyy-MM).",
            snippet: "{{ formatDate(start, \"MMM yyyy\") }}"
        ),
        TextFilterInfo(
            name: "uppercase",
            signature: "uppercase(text)",
            description: "Uppercases the provided text if present.",
            snippet: "{{ uppercase(section-labels.summary) }}"
        )
    ]
}
