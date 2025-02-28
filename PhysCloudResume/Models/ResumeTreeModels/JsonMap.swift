//
//  JsonMap.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/4/25.
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
        "section-labels": .object,
        "contact": .complex,
        "summary": .string,
        "employment": .complex,
        "education": .complex,
        "skills-and-expertise": .twoKeyObjectArray(keyOne: "title", keyTwo: "description"),
        "languages": .array,
        "projects-highlights": .twoKeyObjectArray(keyOne: "name", keyTwo: "description"),
        "projects-and-hobbies": .complex,
        "publications": .complex,
        "more-info": .string,
        "include-fonts": .string,
    ]
    static let specialKeys: [String] = ["font-sizes", "include-fonts"]
}
