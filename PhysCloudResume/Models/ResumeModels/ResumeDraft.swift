//
//  ResumeDraft.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/15/24.
//

import Foundation
import SwiftData


@Model
class ResumeDraft: Identifiable {
    @Attribute(.unique) var id: String
//    var enabledSources: [ResRef]
//    var template: ResumeTemplate
    var content: String
    var name: String

    init(name: String, content: String, id: String = UUID().uuidString) {
        self.id = id
        self.content = content
        self.name = name
    }

}

