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
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // Events Tab
                VStack(spacing: 0) {
                    // Metrics section
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
                    // Events section
                    GroupBox {
                        if events.isEmpty {
                            ContentUnavailableView {
                                Label("No Events", systemImage: "tray.fill")
                            } description: {
                                Text("Event history is empty")
                            }
                        } else {
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
                .tabItem { Label("Events", systemImage: "list.bullet") }
                .tag(0)

                // Conversation Log Tab
                VStack(spacing: 0) {
                    if conversationEntries.isEmpty {
                        ContentUnavailableView {
                            Label("No Messages", systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            Text("Conversation log is empty")
                        }
                    } else {
                        List {
                            ForEach(conversationEntries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.formattedTimestamp)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(entry.type.rawValue)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(colorForType(entry.type))
                                        Spacer()
                                    }
                                    Text(entry.content)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                    if !entry.metadata.isEmpty {
                                        Text("meta: " + entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .listRowSeparator(.visible)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
                .tag(1)
            }
            .navigationTitle("Debug Logs")
            .toolbar {
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
            .task {
                loadEvents()
                loadConversationLog()
            }
        }
        .frame(width: 800, height: 600)
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
        case .artifactRecordPersisted(let record):
            return "artifactRecordPersisted(id: \(record["id"].stringValue))"
        case .knowledgeCardPersisted(let card):
            return "knowledgeCardPersisted(title: \(card["title"].stringValue))"
        default:
            return "\(event)"
        }
    }
    private func formatMetrics(_ metrics: EventCoordinator.EventMetrics) -> String {
        var lines: [String] = []
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
            // Note: Streaming events are now consolidated at source in EventCoordinator
            // The consolidation function below is kept for backward compatibility
            let consolidatedEvents = self.consolidateStreamingEvents(events)
            let countInfo = consolidatedEvents.count < events.count
                ? " (consolidated from \(events.count))"
                : ""
            output += "Recent Events (\(consolidatedEvents.count)\(countInfo)):\n\n"
            for (index, event) in consolidatedEvents.enumerated() {
                output += "#\(consolidatedEvents.count - index)\n"
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
    private func consolidateStreamingEvents(_ events: [String]) -> [String] {
        guard !events.isEmpty else { return [] }
        var consolidated: [String] = []
        var currentMessageId: String?
        var streamingUpdateCount = 0
        var totalChars = 0
        for event in events {
            // Check if this is a streamingMessageUpdated event
            if event.hasPrefix("streamingMessageUpdated(id: ") {
                // Extract message ID from event string (first 8 chars of UUID)
                let idStartIndex = event.index(event.startIndex, offsetBy: "streamingMessageUpdated(id: ".count)
                let idEndIndex = event.index(idStartIndex, offsetBy: 8)
                let messageId = String(event[idStartIndex..<idEndIndex])
                // Extract character count
                if let deltaRange = event.range(of: "delta: "),
                   let charsRange = event.range(of: " chars", range: deltaRange.upperBound..<event.endIndex) {
                    let countString = event[deltaRange.upperBound..<charsRange.lowerBound]
                    if let count = Int(countString) {
                        if currentMessageId == messageId {
                            // Same message - accumulate
                            streamingUpdateCount += 1
                            totalChars += count
                        } else {
                            // Different message - flush previous if exists
                            if let prevId = currentMessageId, streamingUpdateCount > 0 {
                                consolidated.append("streamingMessageUpdated(id: \(prevId)) - \(streamingUpdateCount) updates, \(totalChars) chars total")
                            }
                            // Start new accumulation
                            currentMessageId = messageId
                            streamingUpdateCount = 1
                            totalChars = count
                        }
                        continue
                    }
                }
            }
            // Not a streaming update - flush accumulated if exists
            if let prevId = currentMessageId, streamingUpdateCount > 0 {
                consolidated.append("streamingMessageUpdated(id: \(prevId)) - \(streamingUpdateCount) updates, \(totalChars) chars total")
                currentMessageId = nil
                streamingUpdateCount = 0
                totalChars = 0
            }
            // Add the non-streaming event
            consolidated.append(event)
        }
        // Flush any remaining accumulated streaming events
        if let prevId = currentMessageId, streamingUpdateCount > 0 {
            consolidated.append("streamingMessageUpdated(id: \(prevId)) - \(streamingUpdateCount) updates, \(totalChars) chars total")
        }
        return consolidated
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
