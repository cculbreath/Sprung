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
    /// Current task status
    var status: TaskStatus
    /// Generated content result (nil until completed)
    var result: GeneratedContent?
    /// Error message if failed
    var error: String?
    /// Token usage statistics
    var tokenUsage: TokenUsage?

    init(
        id: UUID = UUID(),
        section: ExperienceSectionKey,
        targetId: String? = nil,
        displayName: String,
        status: TaskStatus = .pending,
        result: GeneratedContent? = nil,
        error: String? = nil,
        tokenUsage: TokenUsage? = nil
    ) {
        self.id = id
        self.section = section
        self.targetId = targetId
        self.displayName = displayName
        self.status = status
        self.result = result
        self.error = error
        self.tokenUsage = tokenUsage
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

    init(inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}
