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

// MARK: - SwiftData Schema Versions
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
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

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 1)

    static var models: [any PersistentModel.Type] = SchemaV1.models + [TemplateSeed.self]
}

// MARK: - Migration Plan
enum PhysCloudResumeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    // MARK: - Migration Stages
    
    /// Single-step migration that brings the legacy store forward to include template seeds
    static let migrateV1toV2: MigrationStage = .lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}

// MARK: - Model Container Factory
extension ModelContainer {
    /// Creates a model container with the migration plan
    static func createWithMigration() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SchemaV2.models),
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        return try ModelContainer(
            for: Schema(SchemaV2.models),
            migrationPlan: PhysCloudResumeMigrationPlan.self,
            configurations: configuration
        )
    }
    
    /// Creates a model container for a specific URL with migration support
    static func createWithMigration(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SchemaV2.models),
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: Schema(SchemaV2.models),
            migrationPlan: PhysCloudResumeMigrationPlan.self,
            configurations: configuration
        )
    }
}
