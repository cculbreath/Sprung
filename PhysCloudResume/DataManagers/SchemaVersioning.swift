//
//  SchemaVersioning.swift
//  PhysCloudResume
//
//  Maintains the canonical list of SwiftData models used by the app.
//  We rely on SwiftData's built-in lightweight migration when the model
//  set changes (e.g. adding TemplateSeed). No custom migration plan is
//  required while we're only adding new entities.
//

import Foundation
import SwiftData

enum PhysCloudSchema {
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
        ResModel.self,
        ConversationContext.self,
        ConversationMessage.self,
        EnabledLLM.self,
        Template.self,
        TemplateAsset.self,
        TemplateSeed.self
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
            schema: PhysCloudSchema.schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        return try ModelContainer(
            for: PhysCloudSchema.schema,
            configurations: configuration
        )
    }

    /// Convenience initializer that targets a specific store URL.
    static func createWithMigration(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: PhysCloudSchema.schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: PhysCloudSchema.schema,
            configurations: configuration
        )
    }
}
