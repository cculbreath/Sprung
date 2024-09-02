
//
//  ResRef.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/15/24.
//

import Foundation
import SwiftData

enum SourceType: String, CaseIterable, Identifiable, Decodable {
    case background = "Background Resource"
    case resumeSource = "Model Resume"
    case jsonSource = "Model JSON"

    var id: String { self.rawValue }
}

@Model
class ResRef: Identifiable {
    var id: String
    var content: String
    var name: String
    var enabledByDefault: Bool
    private var typeRawValue: String

    var type: SourceType {
        get {
            return SourceType(rawValue: typeRawValue) ?? .background
        }
        set {
            typeRawValue = newValue.rawValue
        }
    }

    // Custom Decodable initializer


    // CodingKeys enum


    // Initializer for custom creation
    init(name: String = "", content: String = "", type: SourceType = SourceType.background, enabledByDefault: Bool = false) {
        self.id = UUID().uuidString
        self.content = content
        self.name = name
        self.typeRawValue = type.rawValue
        self.enabledByDefault = enabledByDefault
    }
}
