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
        Logger.debug("🔄 Checking database schema...")
        
        // First, try to fix any schema issues with direct SQL
        do {
            try DatabaseSchemaFixer.fixDatabaseSchema()
        } catch {
            Logger.warning("⚠️ Could not fix database schema: \(error)")
        }
        
        // Try to fetch conversation contexts to see if the table exists
        do {
            let descriptor = FetchDescriptor<ConversationContext>()
            _ = try modelContext.fetch(descriptor)
            Logger.debug("✅ ConversationContext table exists in default.store")
        } catch {
            if error.localizedDescription.contains("no such table") {
                Logger.warning("⚠️ ConversationContext table missing in default.store - creating schema")
                attemptSchemaCreation(modelContext: modelContext)
            } else {
                Logger.error("❌ Error checking database schema: \(error)")
            }
        }
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
            Logger.error("❌ Failed to create database schema: \(error)")
            Logger.error("Error details: \(error.localizedDescription)")
        }
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
            Logger.error("❌ Failed to reset conversation tables: \(error)")
        }
    }
}