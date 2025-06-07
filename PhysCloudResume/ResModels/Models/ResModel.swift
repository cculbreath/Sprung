//
//  ResModel.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import Foundation
import SwiftData

@Model
class ResModel: Identifiable, Equatable, Hashable, Codable {
    var id: UUID
    var dateCreated: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Resume.model) var resumes: [Resume]
    var name: String
    var json: String
    var renderedResumeText: String
    var style: String
    var includeFonts: Bool = false
    
    // Template customization
    var useNativeGeneration: Bool = true
    var customTemplateHTML: String?
    var customTemplateText: String?
    var templateName: String? // Custom template name if using custom templates

    // Override the initializer to set the type to '.jsonSource'
    init(
        resumes: [Resume] = [],
        name: String,
        json: String,
        renderedResumeText: String,
        style: String = "Typewriter"
    ) {
        id = UUID()
        self.resumes = resumes
        self.name = name
        self.json = json
        self.renderedResumeText = renderedResumeText
        self.style = style
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case dateCreated
        case name
        case json
        case renderedResumeText
        case style
        case includeFonts
        case useNativeGeneration
        case customTemplateHTML
        case customTemplateText
        case templateName
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        name = try container.decode(String.self, forKey: .name)
        json = try container.decode(String.self, forKey: .json)
        renderedResumeText = try container.decode(String.self, forKey: .renderedResumeText)
        style = try container.decode(String.self, forKey: .style)
        includeFonts = try container.decode(Bool.self, forKey: .includeFonts)
        useNativeGeneration = try container.decodeIfPresent(Bool.self, forKey: .useNativeGeneration) ?? true
        customTemplateHTML = try container.decodeIfPresent(String.self, forKey: .customTemplateHTML)
        customTemplateText = try container.decodeIfPresent(String.self, forKey: .customTemplateText)
        templateName = try container.decodeIfPresent(String.self, forKey: .templateName)
        resumes = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(name, forKey: .name)
        try container.encode(json, forKey: .json)
        try container.encode(renderedResumeText, forKey: .renderedResumeText)
        try container.encode(style, forKey: .style)
        try container.encode(includeFonts, forKey: .includeFonts)
        try container.encode(useNativeGeneration, forKey: .useNativeGeneration)
        try container.encodeIfPresent(customTemplateHTML, forKey: .customTemplateHTML)
        try container.encodeIfPresent(customTemplateText, forKey: .customTemplateText)
        try container.encodeIfPresent(templateName, forKey: .templateName)
    }
}
