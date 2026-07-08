//
//  GenerationTask.swift
//  Sprung
//
//  Atomic unit of LLM generation work in the Seed Generation Module.
//

import Foundation

/// Atomic unit of LLM generation work
struct GenerationTask: Identifiable, Equatable {
    let id: UUID
    /// Section this task generates content for
    let section: ExperienceSectionKey
    /// Timeline entry ID if this task is entry-specific
    let targetId: String?
    /// Human-readable description (e.g., "Work highlights: Anthropic")
    let displayName: String
    /// Type name of the generator that created this task (e.g., "TitleOptionsGenerator")
    let generatorType: String
    /// Current task status
    var status: TaskStatus

    init(
        id: UUID = UUID(),
        section: ExperienceSectionKey,
        targetId: String? = nil,
        displayName: String,
        generatorType: String = "",
        status: TaskStatus = .pending
    ) {
        self.id = id
        self.section = section
        self.targetId = targetId
        self.displayName = displayName
        self.generatorType = generatorType
        self.status = status
    }

    /// Task execution status
    enum TaskStatus: String, Equatable {
        case pending
        case running
        case completed
        case failed
        case approved
        case rejected
    }
}

/// Token usage statistics for a generation task
struct TokenUsage: Equatable, Codable {
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }
}
