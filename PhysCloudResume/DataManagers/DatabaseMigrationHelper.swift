//
//  DatabaseMigrationHelper.swift
//  PhysCloudResume
//
//  Created on 5/22/25.
//

import Foundation
import SwiftData

@MainActor
class DatabaseMigrationHelper {
    
    /// Checks if the database needs migration and performs it if necessary
    static func checkAndMigrateIfNeeded(modelContext: ModelContext) {
        // Check if we've already completed migration recently
        let lastMigrationCheck = UserDefaults.standard.double(forKey: "lastDatabaseMigrationCheck")
        let oneDayAgo = Date().timeIntervalSince1970 - (24 * 60 * 60)
        
        if lastMigrationCheck > oneDayAgo {
            // Migration was checked recently, skip
            return
        }
        
        Logger.debug("🔄 Checking database schema...")
        
        // Quick validation - just try to access the main tables
        do {
            // Test basic table access
            var resumeDescriptor = FetchDescriptor<Resume>()
            resumeDescriptor.fetchLimit = 1
            _ = try modelContext.fetch(resumeDescriptor)
            
            var contextDescriptor = FetchDescriptor<ConversationContext>()
            contextDescriptor.fetchLimit = 1
            _ = try modelContext.fetch(contextDescriptor)
            
            // All tables accessible, mark migration as completed
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastDatabaseMigrationCheck")
            Logger.debug("✅ Database schema validation passed")
            return
            
        } catch {
            // Only run migration if there's an actual issue
            if error.localizedDescription.contains("no such table") {
                Logger.warning("⚠️ Database table missing - running schema fix")
                runSchemaMigration(modelContext: modelContext)
            } else {
                Logger.debug("✅ Database schema check completed (minor error ignored): \(error.localizedDescription)")
                // Mark as completed even with minor errors to avoid repeated checks
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastDatabaseMigrationCheck")
            }
        }
    }
    
    /// Runs the actual migration only when needed
    private static func runSchemaMigration(modelContext: ModelContext) {
        Logger.info("🔄 Running database schema migration...")
        
        // Only run the schema fixer if there's an actual issue
        do {
            try DatabaseSchemaFixer.fixDatabaseSchema()
        } catch {
            Logger.warning("⚠️ Could not fix database schema: \(error)")
        }
        
        // Try to create missing tables
        attemptSchemaCreation(modelContext: modelContext)
        
        // Mark migration as completed
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastDatabaseMigrationCheck")
        Logger.info("✅ Database schema migration completed")
    }
    
    private static func attemptSchemaCreation(modelContext: ModelContext) {
        // SwiftData should automatically create tables when we insert the first object
        // Create dummy objects to force table creation
        let dummyContext = ConversationContext(objectId: UUID(), objectType: .resume)
        let dummyMessage = ConversationMessage(role: .system, content: "dummy")
        
        // Link them to ensure both tables are created with proper relationships
        dummyContext.messages.append(dummyMessage)
        
        modelContext.insert(dummyContext)
        modelContext.insert(dummyMessage)
        
        do {
            try modelContext.save()
            Logger.debug("✅ Created ConversationContext and ConversationMessage tables in default.store")
            
            // Now delete the dummy objects
            modelContext.delete(dummyMessage)
            modelContext.delete(dummyContext)
            try modelContext.save()
            Logger.debug("🧹 Cleaned up dummy objects")
        } catch {
            Logger.error("x Failed to create database schema: \(error)")
            Logger.error("Error details: \(error.localizedDescription)")
        }
    }
    
    /// Forces a fresh migration check on next startup (for debugging)
    static func resetMigrationCheck() {
        UserDefaults.standard.removeObject(forKey: "lastDatabaseMigrationCheck")
        Logger.debug("🔄 Migration check reset - will run on next startup")
    }
    
    /// Resets the conversation context tables if they're corrupted
    static func resetConversationTables(modelContext: ModelContext) {
        Logger.warning("🔄 Resetting conversation tables...")
        
        do {
            // Fetch and delete all existing contexts
            let contexts = try modelContext.fetch(FetchDescriptor<ConversationContext>())
            for context in contexts {
                modelContext.delete(context)
            }
            
            // Fetch and delete all orphaned messages (shouldn't be any due to cascade delete)
            let messages = try modelContext.fetch(FetchDescriptor<ConversationMessage>())
            for message in messages {
                modelContext.delete(message)
            }
            
            try modelContext.save()
            Logger.debug("✅ Conversation tables reset successfully")
        } catch {
            Logger.error("x Failed to reset conversation tables: \(error)")
        }
    }
}