//
//  SchemaVersioning.swift
//  PhysCloudResume
//
//  Created on 5/24/25.
//
//  Implements SwiftData schema versioning and migration plan
//  to enable automatic database migrations.

import Foundation
import SwiftData

// MARK: - Legacy Schema (pre-TemplateSeed)
enum SchemaLegacy: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
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
            TemplateAsset.self
        ]
    }
}

// MARK: - Current Schema (Template Seeds + future additions)
enum SchemaCurrent: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        var legacy = SchemaLegacy.models
        legacy.append(TemplateSeed.self)
        return legacy
    }
}

// MARK: - Migration Plan
enum PhysCloudResumeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaLegacy.self, SchemaCurrent.self]
    }

    static var stages: [MigrationStage] {
        [migrateLegacyToCurrent]
    }
    
    // MARK: - Migration Stages
    
    /// Single-step migration that brings the legacy store forward to include template seeds
    static let migrateLegacyToCurrent = MigrationStage.lightweight(
        fromVersion: SchemaLegacy.self,
        toVersion: SchemaCurrent.self
    )
    
    /// Removes any temporary objects that were created by DatabaseMigrationHelper
    private static func cleanupTemporaryFixes(context: ModelContext) {
        do {
            // Remove any dummy conversation contexts that were created
            let contexts = try context.fetch(FetchDescriptor<ConversationContext>())
            for conversationContext in contexts {
                if conversationContext.messages.count == 1,
                   let message = conversationContext.messages.first,
                   message.content == "dummy" {
                    context.delete(conversationContext)
                    Logger.debug("🧹 Removed dummy conversation context")
                }
            }
            
            try context.save()
        } catch {
            Logger.warning("⚠️ Could not clean up temporary fixes: \(error)")
        }
    }

}

// MARK: - Model Container Factory
extension ModelContainer {
    /// Creates a model container with the migration plan
    static func createWithMigration() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SchemaCurrent.models),
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        return try ModelContainer(
            for: Schema(SchemaCurrent.models),
            migrationPlan: PhysCloudResumeMigrationPlan.self,
            configurations: configuration
        )
    }
    
    /// Creates a model container for a specific URL with migration support
    static func createWithMigration(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SchemaCurrent.models),
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: Schema(SchemaCurrent.models),
            migrationPlan: PhysCloudResumeMigrationPlan.self,
            configurations: configuration
        )
    }
}
