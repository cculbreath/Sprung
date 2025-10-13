//
//  SectionType.swift
//  Sprung
//
//  Created by Christopher Culbreath on 2/27/25.
//

import Foundation

/// Defines different section types.
enum SectionType {
    case object
    case array
    case complex
    case string
    case mapOfStrings
    case arrayOfObjects
    case fontSizes
}

extension SectionType {
    init?(manifestKind: TemplateManifest.Section.Kind) {
        switch manifestKind {
        case .string:
            self = .string
        case .array:
            self = .array
        case .object:
            self = .object
        case .mapOfStrings:
            self = .mapOfStrings
        case .objectOfObjects:
            self = .complex
        case .arrayOfObjects:
            self = .arrayOfObjects
        case .fontSizes:
            self = .fontSizes
        }
    }
}
