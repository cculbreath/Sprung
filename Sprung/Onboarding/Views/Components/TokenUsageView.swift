//
//  TokenUsageView.swift
//  Sprung
//
//  UI components for displaying token usage statistics in the onboarding interview.
//

import SwiftUI

// MARK: - Token Usage Tab Content

/// Main container for the Token Usage tab showing usage breakdown
struct TokenUsageTabContent: View {
    @Bindable var tracker: TokenUsageTracker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Session summary
                SessionSummaryCard(tracker: tracker)

                // Usage by source
                if !tracker.statsBySource.isEmpty {
                    UsageBySourceCard(tracker: tracker)
                }

                // Usage by model
                if !tracker.statsByModel.isEmpty {
                    UsageByModelCard(tracker: tracker)
                }

                // Cache efficiency
                if tracker.totalStats.inputTokens > 0 {
                    CacheEfficiencyCard(tracker: tracker)
                }
            }
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Session Summary Card

struct SessionSummaryCard: View {
    let tracker: TokenUsageTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Session Summary")
                    .font(.headline)
                Spacer()
                Text(tracker.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            let stats = tracker.totalStats
            HStack(spacing: 24) {
                StatItem(
                    label: "Total Tokens",
                    value: TokenUsageTracker.formatTokenCount(stats.totalTokens),
                    icon: "sum"
                )
                StatItem(
                    label: "Requests",
                    value: "\(stats.requestCount)",
                    icon: "arrow.up.arrow.down"
                )
                StatItem(
                    label: "Input",
                    value: TokenUsageTracker.formatTokenCount(stats.inputTokens),
                    icon: "arrow.up"
                )
                StatItem(
                    label: "Output",
                    value: TokenUsageTracker.formatTokenCount(stats.outputTokens),
                    icon: "arrow.down"
                )
            }

            if stats.reasoningTokens > 0 {
                HStack {
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)
                        .font(.caption)
                    Text("Reasoning tokens: \(TokenUsageTracker.formatTokenCount(stats.reasoningTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Usage by Source Card

struct UsageBySourceCard: View {
    let tracker: TokenUsageTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.green)
                Text("Usage by Source")
                    .font(.headline)
            }

            Divider()

            ForEach(tracker.sourcesSortedByUsage, id: \.source) { item in
                HStack {
                    Image(systemName: item.source.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(item.source.displayName)
                        .font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(TokenUsageTracker.formatTokenCount(item.stats.totalTokens))
                            .font(.subheadline.monospacedDigit())
                        Text("\(item.stats.requestCount) req")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Usage by Model Card

struct UsageByModelCard: View {
    let tracker: TokenUsageTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.orange)
                Text("Usage by Model")
                    .font(.headline)
            }

            Divider()

            ForEach(tracker.modelsSortedByUsage, id: \.modelId) { item in
                HStack {
                    Text(shortModelName(item.modelId))
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("↑\(TokenUsageTracker.formatTokenCount(item.stats.inputTokens))")
                                .foregroundStyle(.blue)
                            Text("↓\(TokenUsageTracker.formatTokenCount(item.stats.outputTokens))")
                                .foregroundStyle(.green)
                        }
                        .font(.caption.monospacedDigit())
                        Text("\(item.stats.requestCount) req")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func shortModelName(_ fullId: String) -> String {
        // Extract meaningful part of model ID
        // e.g., "openai/gpt-4o" -> "gpt-4o"
        // e.g., "anthropic/claude-3.5-sonnet" -> "claude-3.5-sonnet"
        if let lastSlash = fullId.lastIndex(of: "/") {
            return String(fullId[fullId.index(after: lastSlash)...])
        }
        return fullId
    }
}

// MARK: - Cache Efficiency Card

struct CacheEfficiencyCard: View {
    let tracker: TokenUsageTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "memorychip")
                    .foregroundStyle(.purple)
                Text("Cache Efficiency")
                    .font(.headline)
            }

            Divider()

            let stats = tracker.totalStats
            let cacheRate = stats.cacheHitRate

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cache Hit Rate")
                        .font(.subheadline)
                    Spacer()
                    Text(TokenUsageTracker.formatPercentage(cacheRate))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(cacheRate > 0.5 ? .green : cacheRate > 0.2 ? .orange : .secondary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(cacheRate > 0.5 ? Color.green : cacheRate > 0.2 ? Color.orange : Color.secondary)
                            .frame(width: geometry.size.width * cacheRate, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Cached: \(TokenUsageTracker.formatTokenCount(stats.cachedTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total Input: \(TokenUsageTracker.formatTokenCount(stats.inputTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if cacheRate > 0.3 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Good cache utilization - previous turns being reused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact Token Usage Badge

/// A compact badge showing token usage, suitable for headers or status bars
struct TokenUsageBadge: View {
    let tracker: TokenUsageTracker

    var body: some View {
        let stats = tracker.totalStats
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.caption2)
            Text(TokenUsageTracker.formatTokenCount(stats.totalTokens))
                .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
        .help("Total tokens used: \(stats.totalTokens.formatted())")
    }
}
