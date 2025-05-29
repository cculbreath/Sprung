//
//  TestModelContainer.swift
//  PhysCloudResumeTests
//
//  Created on 5/24/25.
//
//  Helper to create test model containers with proper migration support

import Foundation
import SwiftData

extension ModelContainer {
    /// Creates an in-memory container for testing with migration support
    static func createForTesting() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SchemaV2.models),
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        
        return try ModelContainer(
            for: Schema(SchemaV2.models),
            migrationPlan: PhysCloudResumeMigrationPlan.self,
            configurations: configuration
        )
    }
    
    /// Creates a file-based container for testing with migration support
    static func createForTesting(at url: URL) throws -> ModelContainer {
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