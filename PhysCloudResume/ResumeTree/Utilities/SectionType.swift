//
//  SectionType.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

//
//  SectionType.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/4/25.
//

import Foundation

/// Defines different section types.
enum SectionType {
    case object
    case array
    case complex
    case string
    case mapOfStrings
    case twoKeyObjectArray(keyOne: String, keyTwo: String)
    case fontSizes
}

extension SectionType {
    init?(manifestKind: TemplateManifest.Section.Kind, key: String) {
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
            // Prefer specialized handling for known two-key sections
            if key == "skills-and-expertise" || key == "projects-highlights" {
                self = .twoKeyObjectArray(keyOne: "title", keyTwo: "description")
            } else {
                self = .complex
            }
        case .fontSizes:
            self = .fontSizes
        }
    }
}
