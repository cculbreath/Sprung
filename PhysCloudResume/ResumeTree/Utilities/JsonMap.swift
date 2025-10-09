//
//  JsonMap.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

//
//  SectionMappings.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/4/25.
//

import Foundation

/// Maps section names to their corresponding `SectionType`.
enum JsonMap {
    static let sectionKeyToTypeDict: [String: SectionType] = [
        "meta": .object,
        "font-sizes": .fontSizes,
        "keys-in-editor": .array,
        "job-titles": .array,
        "section-labels": .mapOfStrings,
        "contact": .complex,
        "summary": .string,
        "employment": .complex,
        "education": .complex,
        "skills-and-expertise": .arrayOfObjects,
        "languages": .array,
        "projects-highlights": .arrayOfObjects,
        "projects-and-hobbies": .complex,
        "publications": .complex,
        "more-info": .string,
        "include-fonts": .string,
    ]
    /// Deterministic order for section emission
    static let orderedSectionKeys: [String] = [
        "meta",
        "font-sizes",
        "include-fonts",
        "section-labels",
        "contact",
        "summary",
        "job-titles",
        "employment",
        "education",
        "skills-and-expertise",
        "languages",
        "projects-highlights",
        "projects-and-hobbies",
        "publications",
        "keys-in-editor",
        "more-info",
    ]
    static let specialKeys: [String] = ["font-sizes", "include-fonts"]
}
