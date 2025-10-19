//
//  SchemaVersioning.swift
//  Sprung
//
//  Maintains the canonical list of SwiftData models used by the app.
//  We rely on SwiftData's built-in lightweight migration when the model
//  set changes (e.g. adding TemplateSeed). No custom migration plan is
//  required while we're only adding new entities.
//

import Foundation
import SwiftData

enum SprungSchema {
    static let models: [any PersistentModel.Type] = [
        JobApp.self,
        Resume.self,
        ResRef.self,
        TreeNode.self,
        FontSizeNode.self,
        CoverLetter.self,
        MessageParams.self,
        CoverRef.self,
        ApplicantProfile.self,
        ApplicantSocialProfile.self,
        ConversationContext.self,
        ConversationMessage.self,
        EnabledLLM.self,
        Template.self,
        TemplateAsset.self,
        TemplateSeed.self,
        ExperienceDefaults.self,
        WorkExperienceDefault.self,
        WorkHighlightDefault.self,
        VolunteerExperienceDefault.self,
        VolunteerHighlightDefault.self,
        EducationExperienceDefault.self,
        EducationCourseDefault.self,
        ProjectExperienceDefault.self,
        ProjectHighlightDefault.self,
        ProjectKeywordDefault.self,
        ProjectRoleDefault.self,
        SkillExperienceDefault.self,
        SkillKeywordDefault.self,
        AwardExperienceDefault.self,
        CertificateExperienceDefault.self,
        PublicationExperienceDefault.self,
        LanguageExperienceDefault.self,
        InterestExperienceDefault.self,
        InterestKeywordDefault.self,
        ReferenceExperienceDefault.self
    ]

    static var schema: Schema {
        Schema(models)
    }
}

extension ModelContainer {
    /// Creates a model container using the canonical schema. SwiftData will
    /// automatically perform lightweight migration when we add new models.
    static func createWithMigration() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: SprungSchema.schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        return try ModelContainer(
            for: SprungSchema.schema,
            configurations: configuration
        )
    }

}
