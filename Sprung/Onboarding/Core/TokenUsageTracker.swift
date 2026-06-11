//
//  TokenUsageTracker.swift
//  Sprung
//
//  Tracks token usage across the onboarding interview session.
//  Provides per-model breakdowns and totals for input, output, cached, and reasoning tokens.
//

import Foundation
import Observation
import SwiftOpenAI

// MARK: - Usage Entry

/// A single usage record from an API call.
/// Note on semantics: for Anthropic, `inputTokens` EXCLUDES cache reads/creation
/// (the API reports them separately); cacheReadTokens were served from the prompt
/// cache at 0.1x cost and cacheCreationTokens were written to it.
struct TokenUsageEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let modelId: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int
    let source: UsageSource

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        reasoningTokens: Int = 0,
        source: UsageSource
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.source = source
    }
}

/// Source of token usage
enum UsageSource: String, Codable, CaseIterable {
    case mainCoordinator = "main_coordinator"
    case cardGeneration = "card_generation"
    case gitAgent = "git_agent"
    case documentExtraction = "doc_extraction"
    case documentSummarization = "doc_summary"

    var displayName: String {
        switch self {
        case .mainCoordinator: return "Main Coordinator"
        case .cardGeneration: return "Card Generation"
        case .gitAgent: return "Git Analysis"
        case .documentExtraction: return "Doc Extraction"
        case .documentSummarization: return "Doc Summary"
        }
    }

    var icon: String {
        switch self {
        case .mainCoordinator: return "bubble.left.and.bubble.right"
        case .cardGeneration: return "rectangle.stack.fill"
        case .gitAgent: return "chevron.left.forwardslash.chevron.right"
        case .documentExtraction: return "doc.text.magnifyingglass"
        case .documentSummarization: return "doc.text"
        }
    }
}

// MARK: - Aggregated Stats

/// Aggregated token statistics
struct TokenUsageStats: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var reasoningTokens: Int = 0
    var requestCount: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// Total prompt tokens processed, including cache reads and creation
    var totalPromptTokens: Int {
        inputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// Fraction of all prompt tokens that were served from cache (0.1x cost).
    /// Denominator includes cache reads/creation since Anthropic reports them
    /// separately from inputTokens.
    var cacheHitRate: Double {
        guard totalPromptTokens > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(totalPromptTokens)
    }

    /// Cache hit rate over tokens that COULD have been served from cache:
    /// cacheRead / (input + cacheRead). Excludes cache-creation tokens from
    /// the denominator (unlike `cacheHitRate`, which measures the cached
    /// fraction of ALL prompt tokens including writes).
    var hitRate: Double {
        let denominator = inputTokens + cacheReadTokens
        guard denominator > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(denominator)
    }

    mutating func add(_ entry: TokenUsageEntry) {
        inputTokens += entry.inputTokens
        outputTokens += entry.outputTokens
        cacheReadTokens += entry.cacheReadTokens
        cacheCreationTokens += entry.cacheCreationTokens
        reasoningTokens += entry.reasoningTokens
        requestCount += 1
    }

    mutating func add(_ other: TokenUsageStats) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheCreationTokens += other.cacheCreationTokens
        reasoningTokens += other.reasoningTokens
        requestCount += other.requestCount
    }
}

// MARK: - Token Usage Tracker

/// Central tracker for all token usage across the interview session.
/// Observable for SwiftUI integration.
@Observable
@MainActor
class TokenUsageTracker {
    // MARK: - State

    /// All usage entries (for detailed history)
    private(set) var entries: [TokenUsageEntry] = []

    /// Stats aggregated by model ID
    private(set) var statsByModel: [String: TokenUsageStats] = [:]

    /// Stats aggregated by source
    private(set) var statsBySource: [UsageSource: TokenUsageStats] = [:]

    /// Session start time
    let sessionStartTime: Date

    // MARK: - Computed Properties

    /// Total stats across all models and sources
    var totalStats: TokenUsageStats {
        var total = TokenUsageStats()
        for stats in statsByModel.values {
            total.add(stats)
        }
        return total
    }

    /// Session duration
    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }

    /// Formatted session duration
    var formattedDuration: String {
        let minutes = Int(sessionDuration) / 60
        let seconds = Int(sessionDuration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Models sorted by total usage
    var modelsSortedByUsage: [(modelId: String, stats: TokenUsageStats)] {
        statsByModel.sorted { $0.value.totalTokens > $1.value.totalTokens }
            .map { (modelId: $0.key, stats: $0.value) }
    }

    /// Sources sorted by total usage
    var sourcesSortedByUsage: [(source: UsageSource, stats: TokenUsageStats)] {
        statsBySource.sorted { $0.value.totalTokens > $1.value.totalTokens }
            .map { (source: $0.key, stats: $0.value) }
    }

    // MARK: - Initialization

    init() {
        self.sessionStartTime = Date()
        Logger.info("📊 TokenUsageTracker initialized", category: .ai)
    }

    // MARK: - Event Subscription

    /// Start listening to token usage events from the event bus.
    /// Also watches phase events so a session-total summary is logged once
    /// when the interview completes.
    func startEventSubscription(eventBus: EventCoordinator) {
        Task { @MainActor [weak self] in
            for await event in await eventBus.stream(topic: .llm) {
                guard let self = self else { return }
                if case .llm(.tokenUsageReceived(let modelId, let inputTokens, let outputTokens, let cacheReadTokens, let cacheCreationTokens, let reasoningTokens, let source)) = event {
                    self.recordUsage(
                        modelId: modelId,
                        source: source,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        cacheReadTokens: cacheReadTokens,
                        cacheCreationTokens: cacheCreationTokens,
                        reasoningTokens: reasoningTokens
                    )
                }
            }
        }
        Task { @MainActor [weak self] in
            for await event in await eventBus.stream(topic: .phase) {
                guard let self = self else { return }
                if case .phase(.interviewCompleted) = event {
                    self.logSessionSummary(trigger: "interview complete")
                }
            }
        }
        Logger.info("📊 TokenUsageTracker subscribed to LLM events", category: .ai)
    }

    // MARK: - Recording Usage

    /// Record a usage entry directly
    func recordEntry(_ entry: TokenUsageEntry) {
        entries.append(entry)

        // Update per-model stats
        var modelStats = statsByModel[entry.modelId] ?? TokenUsageStats()
        modelStats.add(entry)
        statsByModel[entry.modelId] = modelStats

        // Update per-source stats
        var sourceStats = statsBySource[entry.source] ?? TokenUsageStats()
        sourceStats.add(entry)
        statsBySource[entry.source] = sourceStats

        Logger.debug(
            "📊 Token usage: +\(entry.inputTokens) in, +\(entry.outputTokens) out (\(entry.modelId), \(entry.source.displayName))",
            category: .ai
        )
    }

    /// Record usage with raw values
    func recordUsage(
        modelId: String,
        source: UsageSource,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        reasoningTokens: Int = 0
    ) {
        let entry = TokenUsageEntry(
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningTokens: reasoningTokens,
            source: source
        )
        recordEntry(entry)
    }

    // MARK: - Session Summary

    /// Log a single session-total readout: totals, overall cache hit-rate,
    /// and a per-category (per-source) breakdown.
    /// Emitted at interview end and on event-dump export.
    func logSessionSummary(trigger: String) {
        let total = totalStats
        guard total.requestCount > 0 else {
            Logger.info("📊 Session token summary (\(trigger)): no usage recorded", category: .ai)
            return
        }

        var lines: [String] = []
        lines.append("📊 Session token summary (\(trigger)) — \(formattedDuration), \(total.requestCount) request(s)")
        lines.append("  totals: in=\(Self.formatTokenCount(total.inputTokens)) out=\(Self.formatTokenCount(total.outputTokens)) cacheRead=\(Self.formatTokenCount(total.cacheReadTokens)) cacheWrite=\(Self.formatTokenCount(total.cacheCreationTokens)) hitRate=\(Self.formatPercentage(total.hitRate))")
        for (source, stats) in sourcesSortedByUsage {
            lines.append("  \(source.displayName): in=\(Self.formatTokenCount(stats.inputTokens)) out=\(Self.formatTokenCount(stats.outputTokens)) cacheRead=\(Self.formatTokenCount(stats.cacheReadTokens)) cacheWrite=\(Self.formatTokenCount(stats.cacheCreationTokens)) hitRate=\(Self.formatPercentage(stats.hitRate)) (\(stats.requestCount) req)")
        }
        Logger.info(lines.joined(separator: "\n"), category: .ai)
    }

}

// MARK: - Formatting Helpers

extension TokenUsageTracker {
    /// Format a token count for display
    static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    /// Format percentage for display
    static func formatPercentage(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
