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

// MARK: - Schema V1 (Original Schema)
enum SchemaV1: VersionedSchema {
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
            ResModel.self
        ]
    }
}

// MARK: - Schema V2 (Added Conversation Models)
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
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
            // New models added in V2
            ConversationContext.self,
            ConversationMessage.self
        ]
    }
}

// MARK: - Schema V3 (EnabledLLM + Template Library)
enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    
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

// MARK: - Schema V4 (Template Seeds)
enum SchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

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
            TemplateAsset.self,
            TemplateSeed.self
        ]
    }
}

// MARK: - Migration Plan
enum PhysCloudResumeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }
    
    // MARK: - Migration Stages
    
    /// Migrates from V1 to V2 by adding conversation models
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            Logger.debug("🔄 Starting migration from Schema V1 to V2...")
            
            // The conversation models will be automatically added by SwiftData
            // No manual migration needed for new models
        },
        didMigrate: { context in
            Logger.debug("✅ Completed migration from Schema V1 to V2")
            
            // Verify the new tables exist
            do {
                let conversationContexts = try context.fetch(FetchDescriptor<ConversationContext>())
                Logger.debug("✅ ConversationContext table created with \(conversationContexts.count) records")
            } catch {
                Logger.warning("⚠️ Could not verify ConversationContext table: \(error)")
            }
            
            // Verify relationships are working
            do {
                // Test Resume-ResRef relationship
                let resumes = try context.fetch(FetchDescriptor<Resume>())
                if let firstResume = resumes.first {
                    _ = firstResume.enabledSources // Access the relationship to ensure it's loaded
                    Logger.debug("✅ Resume-ResRef relationship verified")
                }
                
                // Test other relationships
                let jobApps = try context.fetch(FetchDescriptor<JobApp>())
                if let firstJobApp = jobApps.first {
                    _ = firstJobApp.coverLetters
                    _ = firstJobApp.resumes
                    Logger.debug("✅ JobApp relationships verified")
                }
                
                Logger.debug("✅ All relationships verified in Schema V2")
            } catch {
                Logger.warning("⚠️ Could not verify relationships: \(error)")
            }
            
            // Clean up any temporary fixes that were applied
            cleanupTemporaryFixes(context: context)
        }
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
    
    /// Migrates from V2 to V3 by adding EnabledLLM model
    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self,
        willMigrate: { context in
            Logger.debug("🔄 Starting migration from Schema V2 to V3...")
            
            // The EnabledLLM model will be automatically added by SwiftData
            // No manual migration needed for new models
        },
        didMigrate: { context in
            Logger.debug("✅ Completed migration from Schema V2 to V3")
            
            // Verify the new table exists
            do {
                let enabledModels = try context.fetch(FetchDescriptor<EnabledLLM>())
                Logger.debug("✅ EnabledLLM table created with \(enabledModels.count) records")
            } catch {
                Logger.warning("⚠️ Could not verify EnabledLLM table: \(error)")
            }
            
            Logger.debug("✅ EnabledLLM model migration completed successfully")
        }
    )

    static let migrateV3toV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self,
        willMigrate: { _ in
            Logger.debug("🔄 Starting migration from Schema V3 to V4...")
        },
        didMigrate: { context in
            Logger.debug("✅ Completed migration from Schema V3 to V4")
            do {
                let seeds = try context.fetch(FetchDescriptor<TemplateSeed>())
                Logger.debug("✅ TemplateSeed table ready with \(seeds.count) records")
            } catch {
                Logger.warning("⚠️ Could not verify TemplateSeed table: \(error)")
            }
        }
    )

}

// MARK: - Model Container Factory
extension ModelContainer {
    /// Creates a model container with the migration plan
    static func createWithMigration() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SchemaV4.models),
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        return try ModelContainer(
            for: Schema(SchemaV4.models),
            migrationPlan: PhysCloudResumeMigrationPlan.self,
            configurations: configuration
        )
    }
    
    /// Creates a model container for a specific URL with migration support
    static func createWithMigration(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SchemaV4.models),
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: Schema(SchemaV4.models),
            migrationPlan: PhysCloudResumeMigrationPlan.self,
            configurations: configuration
        )
    }
}
