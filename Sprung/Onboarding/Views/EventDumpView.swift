//
//  EventDumpView.swift
//  Sprung
//
//  Debug view for inspecting recent onboarding events
//
import SwiftUI
import AppKit
#if DEBUG
struct EventDumpView: View {
    let coordinator: OnboardingInterviewCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var events: [String] = []
    @State private var metricsText: String = ""
    @State private var conversationEntries: [ConversationLogEntry] = []
    @State private var selectedTab = 0
    @State private var showRegenDialog = false
    @State private var isDeduping = false

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                eventsTabContent
                    .tabItem { Label("Events", systemImage: "list.bullet") }
                    .tag(0)

                conversationTabContent
                    .tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
                    .tag(1)
            }
            .navigationTitle("Debug Logs")
            .toolbar { toolbarContent }
            .task {
                loadEvents()
                loadConversationLog()
            }
            .sheet(isPresented: $showRegenDialog) {
                regenSheet
            }
        }
        .frame(width: 800, height: 600)
    }

    // MARK: - Tab Content Views

    @ViewBuilder
    private var eventsTabContent: some View {
        VStack(spacing: 0) {
            GroupBox {
                ScrollView {
                    Text(metricsText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 150)
            } label: {
                Text("Event Metrics")
                    .font(.headline)
            }
            .padding()

            GroupBox {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No Events", systemImage: "tray.fill")
                    } description: {
                        Text("Event history is empty")
                    }
                } else {
                    eventsList
                }
            } label: {
                HStack {
                    Text("Recent Events")
                        .font(.headline)
                    Spacer()
                    Text("\(events.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding([.horizontal, .bottom])
        }
    }

    private var eventsList: some View {
        List {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("#\(events.count - index)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                    }
                    Text(event)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var conversationTabContent: some View {
        VStack(spacing: 0) {
            if conversationEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Messages", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Conversation log is empty")
                }
            } else {
                conversationList
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(conversationEntries) { entry in
                conversationEntryRow(entry)
                    .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }

    private func conversationEntryRow(_ entry: ConversationLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            conversationEntryHeader(entry)
            Text(entry.content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            if !entry.metadata.isEmpty {
                Text("meta: " + entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func conversationEntryHeader(_ entry: ConversationLogEntry) -> some View {
        HStack {
            Text(entry.formattedTimestamp)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.type.rawValue)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(colorForType(entry.type))

            Spacer()

            if let tokens = entry.tokenUsage {
                tokenUsageView(tokens)
            }

            if let runningTotal = entry.runningTotal {
                runningTotalView(runningTotal)
            }
        }
    }

    private func tokenUsageView(_ tokens: EntryTokenUsage) -> some View {
        HStack(spacing: 4) {
            Text("In:")
                .foregroundStyle(.tertiary)
            Text(TokenUsageTracker.formatTokenCount(tokens.input))
            Text("Out:")
                .foregroundStyle(.tertiary)
            Text(TokenUsageTracker.formatTokenCount(tokens.output))
            if tokens.cached > 0 {
                Text("Cache:")
                    .foregroundStyle(.tertiary)
                Text(TokenUsageTracker.formatTokenCount(tokens.cached))
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func runningTotalView(_ runningTotal: Int) -> some View {
        HStack(spacing: 2) {
            Text("Total:")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(TokenUsageTracker.formatTokenCount(runningTotal))
                .font(.caption2.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                dismiss()
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Button("Export Events") {
                    exportEventDump()
                }
                Button("Export Conversation Log") {
                    exportConversationLog()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export logs to a text file")
        }
        ToolbarItem(placement: .automatic) {
            Button("Refresh") {
                loadEvents()
                loadConversationLog()
            }
        }
        ToolbarItem(placement: .automatic) {
            Button("Regenerate...") {
                showRegenDialog = true
            }
            .help("Regenerate summaries and/or inventories for selected artifacts")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task {
                    isDeduping = true
                    await coordinator.deduplicateNarratives()
                    isDeduping = false
                }
            } label: {
                if isDeduping {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Deduping...")
                    }
                } else {
                    Text("Dedupe Narratives")
                }
            }
            .disabled(isDeduping)
            .help("Run LLM-powered deduplication on narrative cards")
        }
        ToolbarItem(placement: .automatic) {
            Button("Reset All Data", role: .destructive) {
                Task {
                    await coordinator.resetAllOnboardingData()
                    loadEvents()
                    loadConversationLog()
                }
            }
            .help("Reset ApplicantProfile, remove photo, delete uploads, and clear all interview data")
        }
        ToolbarItem(placement: .destructiveAction) {
            Button("Clear History") {
                Task {
                    await coordinator.clearEventHistory()
                    coordinator.conversationLogStore.clear()
                    loadEvents()
                    loadConversationLog()
                }
            }
        }
    }

    // MARK: - Sheets

    private var regenSheet: some View {
        RegenOptionsDialog(
            artifacts: coordinator.sessionArtifacts.filter { !$0.isWritingSample },
            onConfirm: { selectedIds, operations in
                showRegenDialog = false
                Task {
                    await coordinator.regenerateSelected(
                        artifactIds: selectedIds,
                        regenerateSummary: operations.summary,
                        regenerateInventory: operations.knowledgeExtraction,
                        runMerge: operations.remerge,
                        dedupeNarratives: operations.dedupeNarratives
                    )
                }
            },
            onCancel: {
                showRegenDialog = false
            }
        )
    }
    private func loadEvents() {
        Task {
            let recentEvents = await coordinator.getRecentEvents(count: 1000)
            events = recentEvents.map { formatEvent($0) }
            let metrics = await coordinator.getEventMetrics()
            metricsText = formatMetrics(metrics)
        }
    }
    private func formatEvent(_ event: OnboardingEvent) -> String {
        // Simple format - just use the enum case name and basic info
        switch event {
        case .processingStateChanged(let processing, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processingStateChanged(\(processing))\(statusInfo)"
        case .streamingMessageBegan(let id, _, let reasoningExpected, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "streamingMessageBegan(id: \(id.uuidString.prefix(8)), reasoningExpected: \(reasoningExpected))\(statusInfo)"
        case .streamingMessageUpdated(let id, let delta, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "streamingMessageUpdated(id: \(id.uuidString.prefix(8)), delta: \(delta.count) chars)\(statusInfo)"
        case .streamingMessageFinalized(let id, let text, let toolCalls, _):
            let toolInfo = toolCalls.map { " toolCalls: \($0.count)" } ?? ""
            return "streamingMessageFinalized(id: \(id.uuidString.prefix(8)), text: \(text.count) chars\(toolInfo))"
        case .llmReasoningSummaryDelta(let delta):
            return "llmReasoningSummaryDelta(\(delta.prefix(50))...)"
        case .llmReasoningSummaryComplete(let text):
            return "llmReasoningSummaryComplete(\(text.count) chars)"
        case .toolCallRequested(let call, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "toolCallRequested(\(call.name))\(statusInfo)"
        case .toolCallCompleted(let id, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "toolCallCompleted(\(id.uuidString.prefix(8)))\(statusInfo)"
        case .objectiveStatusChanged(let id, let oldStatus, let newStatus, let phase, _, _, _):
            return "objectiveStatusChanged(\(id): \(oldStatus ?? "nil") → \(newStatus), phase: \(phase))"
        case .phaseTransitionApplied(let phase, let timestamp):
            return "phaseTransitionApplied(\(phase), \(timestamp.formatted()))"
        case .skeletonTimelineReplaced(_, let diff, _):
            if let diff = diff {
                return "skeletonTimelineReplaced(\(diff.summary))"
            } else {
                return "skeletonTimelineReplaced"
            }
        case .knowledgeCardPersisted(let card):
            return "knowledgeCardPersisted(title: \(card["title"].stringValue))"
        default:
            return "\(event)"
        }
    }
    private func formatMetrics(_ metrics: EventCoordinator.EventMetrics) -> String {
        var lines: [String] = []

        // Token Usage Summary
        let tracker = coordinator.tokenUsageTracker
        let stats = tracker.totalStats
        if stats.requestCount > 0 {
            lines.append("Token Usage Summary:")
            lines.append("  Total Tokens:    \(TokenUsageTracker.formatTokenCount(stats.totalTokens))")
            lines.append("  Input Tokens:    \(TokenUsageTracker.formatTokenCount(stats.inputTokens))")
            lines.append("  Output Tokens:   \(TokenUsageTracker.formatTokenCount(stats.outputTokens))")
            if stats.cachedTokens > 0 {
                lines.append("  Cached Tokens:   \(TokenUsageTracker.formatTokenCount(stats.cachedTokens)) (\(TokenUsageTracker.formatPercentage(stats.cacheHitRate)) hit rate)")
            }
            if stats.reasoningTokens > 0 {
                lines.append("  Reasoning:       \(TokenUsageTracker.formatTokenCount(stats.reasoningTokens))")
            }
            lines.append("  Requests:        \(stats.requestCount)")
            lines.append("  Session Time:    \(tracker.formattedDuration)")
            lines.append("")
        }

        lines.append("Published Event Counts by Topic:")
        for topic in EventTopic.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let count = metrics.publishedCount[topic] ?? 0
            let lastTime = metrics.lastPublishTime[topic]?.formatted(.relative(presentation: .numeric)) ?? "never"
            lines.append("  \(topic.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)): \(count) events (last: \(lastTime))")
        }
        return lines.joined(separator: "\n")
    }
    private func exportEventDump() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "event-dump-\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateSeparator(.dash).dateTimeSeparator(.space).timeSeparator(.colon))).txt"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export Event Dump"
        savePanel.message = "Choose where to save the event dump"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            var output = "Sprung Onboarding Event Dump\n"
            output += "Generated: \(Date().formatted())\n"
            output += String(repeating: "=", count: 80) + "\n\n"
            output += metricsText + "\n\n"
            output += String(repeating: "=", count: 80) + "\n\n"
            output += "Recent Events (\(events.count)):\n\n"
            for (index, event) in events.enumerated() {
                output += "#\(events.count - index)\n"
                output += event + "\n\n"
            }
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
                Logger.info("Event dump exported to: \(url.path)", category: .general)
            } catch {
                Logger.error("Failed to export event dump: \(error.localizedDescription)", category: .general)
            }
        }
    }
    // MARK: - Conversation Log Functions

    private func loadConversationLog() {
        conversationEntries = coordinator.conversationLogStore.getEntries()
    }

    private func colorForType(_ type: ConversationLogEntryType) -> Color {
        switch type {
        case .user: return .blue
        case .assistant: return .green
        case .developer: return .orange
        case .toolCall: return .purple
        case .toolResponse: return .cyan
        case .system: return .gray
        }
    }

    private func exportConversationLog() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "conversation-log-\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateSeparator(.dash).dateTimeSeparator(.space).timeSeparator(.colon))).txt"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export Conversation Log"
        savePanel.message = "Choose where to save the conversation log"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            let output = coordinator.conversationLogStore.exportLog()

            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
                Logger.info("Conversation log exported to: \(url.path)", category: .general)
            } catch {
                Logger.error("Failed to export conversation log: \(error.localizedDescription)", category: .general)
            }
        }
    }
}
#endif
