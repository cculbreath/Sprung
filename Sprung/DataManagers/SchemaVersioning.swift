//
//  SchemaVersioning.swift
//  Sprung
//
//  Maintains the canonical list of SwiftData models used by the app.
//  We rely on SwiftData's built-in lightweight migration when the model
//  set changes. No custom migration plan is required while we're only
//  adding new entities.
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
        ExperienceDefaults.self,
        // Onboarding Session Models
        OnboardingSession.self,
        OnboardingObjectiveRecord.self,
        OnboardingArtifactRecord.self,
        OnboardingMessageRecord.self,
        OnboardingPlanItemRecord.self
    ]
    static var schema: Schema {
        Schema(models)
    }
}
extension ModelContainer {
    /// The app's data store directory
    static var storeDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sprungDir = appSupport.appendingPathComponent("Sprung", isDirectory: true)
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: sprungDir, withIntermediateDirectories: true)
        return sprungDir
    }

    /// The URL for the SwiftData store
    static var storeURL: URL {
        storeDirectory.appendingPathComponent("default.store")
    }

    /// Creates a model container using the canonical schema. SwiftData will
    /// automatically perform lightweight migration when we add new models.
    static func createWithMigration() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: SprungSchema.schema,
            url: storeURL,
            allowsSave: true
        )
        return try ModelContainer(
            for: SprungSchema.schema,
            configurations: configuration
        )
    }
}
