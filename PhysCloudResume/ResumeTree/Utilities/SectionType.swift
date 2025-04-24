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
    case twoKeyObjectArray(keyOne: String, keyTwo: String)
    case fontSizes
}
