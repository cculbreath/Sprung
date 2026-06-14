//
//  EventDumpView.swift
//  Sprung
//
//  Debug view for inspecting recent onboarding events
//
import SwiftUI
import AppKit

struct EventDumpView: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var events: [String] = []
    @State private var metricsText: String = ""
    @State private var conversationEntries: [ConversationLogEntry] = []
    @State private var todoItems: [InterviewTodoItem] = []
    @State private var contextPreview: ContextPreviewSnapshot?
    @State private var selectedTab = 0
    @State private var showRegenDialog = false
    @State private var isDeduping = false
    @State private var isDedupingSkills = false
    @State private var isExpandingATS = false

    // Recordings (session tape recorder)
    @State private var tapeStore = TapeStore()
    @State private var tapeSessions: [TapeSessionSummary] = []
    @State private var expandedSessionId: String?
    @State private var sessionSteps: [TapeStep] = []
    @State private var recordingEnabled = UserDefaults.standard.bool(forKey: InterviewLifecycleController.recordingEnabledKey)
    @State private var replayingSessionId: String?

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                eventsTabContent
                    .tabItem { Label("Events", systemImage: "list.bullet") }
                    .tag(0)

                conversationTabContent
                    .tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
                    .tag(1)

                todoListTabContent
                    .tabItem { Label("Todo List", systemImage: "checklist") }
                    .tag(2)

                contextPreviewTabContent
                    .tabItem { Label("Context", systemImage: "doc.text.magnifyingglass") }
                    .tag(3)

                recordingsTabContent
                    .tabItem { Label("Recordings", systemImage: "recordingtape") }
                    .tag(4)
            }
            .navigationTitle("Debug Logs")
            .toolbar { toolbarContent }
            .task {
                loadEvents()
                loadConversationLog()
                await loadTodoItems()
                await loadContextPreview()
                await loadRecordings()
            }
            .task {
                // Live update todo list when events fire
                for await event in await coordinator.eventBus.streamAll() {
                    if case .tool(.todoListUpdated) = event {
                        await loadTodoItems()
                    }
                }
            }
            .sheet(isPresented: $showRegenDialog) {
                regenSheet
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toastOverlay()
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

    // MARK: - Todo List Tab

    @ViewBuilder
    private var todoListTabContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(todoItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await loadTodoItems() } }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if todoItems.isEmpty {
                Text("Empty").font(.caption).foregroundStyle(.secondary).padding(8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(todoItems.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 4) {
                                Text(statusChar(for: item.status))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(statusColor(for: item.status))
                                Text("\(index + 1).")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text(item.content)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text(item.status.rawValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(item.status == .inProgress ? Color.blue.opacity(0.1) : Color.clear)
                        }
                    }
                }
            }
        }
    }

    private func statusChar(for status: InterviewTodoStatus) -> String {
        switch status {
        case .pending: return "○"
        case .inProgress: return "◐"
        case .completed: return "●"
        }
    }

    private func statusColor(for status: InterviewTodoStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        }
    }

    private func loadTodoItems() async {
        todoItems = await coordinator.todoStore.getItemsForPersistence()
    }

    // MARK: - Context Preview Tab

    @ViewBuilder
    private var contextPreviewTabContent: some View {
        VStack(spacing: 0) {
            if let preview = contextPreview {
                contextPreviewHeader(preview)
                contextPreviewList(preview)
            } else {
                ContentUnavailableView {
                    Label("No Context", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Loading context preview...")
                }
            }
        }
    }

    private func contextPreviewHeader(_ preview: ContextPreviewSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated Context Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Tokens:")
                            .foregroundStyle(.tertiary)
                        Text(TokenUsageTracker.formatTokenCount(preview.totalEstimatedTokens))
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                    HStack(spacing: 4) {
                        Text("Bytes:")
                            .foregroundStyle(.tertiary)
                        Text(formatBytes(preview.totalBytes))
                            .fontWeight(.medium)
                    }
                    HStack(spacing: 4) {
                        Text("Tools:")
                            .foregroundStyle(.tertiary)
                        Text("\(preview.toolCount)")
                        Text("(~\(TokenUsageTracker.formatTokenCount(preview.toolSchemaTokens)) tokens)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption.monospacedDigit())
            }
            Spacer()
            Button("Refresh") {
                Task { await loadContextPreview() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func contextPreviewList(_ preview: ContextPreviewSnapshot) -> some View {
        List {
            ForEach(preview.items) { item in
                contextPreviewItemRow(item)
                    .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }

    private func contextPreviewItemRow(_ item: ContextPreviewItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.type.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(colorForContextType(item.type))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForContextType(item.type).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Text("~\(TokenUsageTracker.formatTokenCount(item.estimatedTokens)) tokens")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(formatBytes(item.byteSize))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            Text(truncateContent(item.content))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(6)
        }
        .padding(.vertical, 4)
    }

    private func colorForContextType(_ type: ContextPreviewItem.ContextItemType) -> Color {
        switch type {
        case .systemPrompt: return .purple
        case .userMessage: return .blue
        case .assistantMessage: return .green
        case .toolCall: return .orange
        case .toolResult: return .cyan
        case .interviewContext: return .indigo
        case .coordinator: return .yellow
        case .document: return .pink
        }
    }

    private func truncateContent(_ content: String) -> String {
        if content.count > 500 {
            return String(content.prefix(500)) + "..."
        }
        return content
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.1f KB", Double(bytes) / 1_000)
        }
        return "\(bytes) B"
    }

    private func loadContextPreview() async {
        let service = ContextPreviewService(
            stateCoordinator: coordinator.state,
            phaseRegistry: coordinator.phaseRegistry,
            toolRegistry: coordinator.toolRegistry,
            todoStore: coordinator.todoStore
        )
        contextPreview = await service.buildPreview()
    }

    // MARK: - Recordings Tab

    @ViewBuilder
    private var recordingsTabContent: some View {
        VStack(spacing: 0) {
            recordingsHeader
            if tapeSessions.isEmpty {
                ContentUnavailableView {
                    Label("No Recordings", systemImage: "recordingtape")
                } description: {
                    Text(recordingEnabled
                         ? "Recording is on. Start a fresh interview to capture a session tape."
                         : "Turn on recording, then start a fresh interview to capture a session tape.")
                }
            } else {
                recordingsList
            }
        }
    }

    private var recordingsHeader: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $recordingEnabled) {
                Text("Record sessions").font(.caption)
            }
            .toggleStyle(.switch)
            .onChange(of: recordingEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: InterviewLifecycleController.recordingEnabledKey)
            }
            .help("Tee the next fresh interview to a session tape (~/Library/Application Support/Sprung/Recordings)")
            Spacer()
            Text("\(tapeSessions.count) of \(RecordingPaths.maxSessions)")
                .font(.caption).foregroundStyle(.secondary)
            Button("Refresh") { Task { await loadRecordings() } }
                .buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var recordingsList: some View {
        List {
            ForEach(tapeSessions) { session in
                recordingRow(session)
                    .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func recordingRow(_ session: TapeSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    Task { await toggleExpanded(session) }
                } label: {
                    Image(systemName: expandedSessionId == session.sessionId ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.recordedAt ?? String(session.sessionId.prefix(8)))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(recordingSummaryLine(session))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    Task { await deleteSession(session) }
                } label: {
                    Image(systemName: "trash").font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Delete this recording")
            }

            if expandedSessionId == session.sessionId {
                ForEach(sessionSteps) { step in
                    HStack(spacing: 6) {
                        Text("#\(step.turnIndex)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(step.kind)
                            .font(.caption2)
                            .foregroundStyle(step.kind == "modelTurn" ? Color.green : Color.blue)
                        Text(step.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let ordinal = step.userMessageOrdinal {
                            Button("Restore →") {
                                runRestore(sessionId: session.sessionId, throughUserMessageOrdinal: ordinal)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .disabled(replayingSessionId != nil)
                            .help("Restart the interview, replay through this message for $0, then go live")
                        }
                    }
                    .padding(.leading, 24)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func recordingSummaryLine(_ session: TapeSessionSummary) -> String {
        var parts = ["\(session.turnCount) turns",
                     "\(session.userMessageCount) msgs",
                     "\(session.toolResultCount) tools"]
        if let model = session.modelId, !model.isEmpty { parts.append(model) }
        return parts.joined(separator: " · ")
    }

    private func loadRecordings() async {
        tapeSessions = await tapeStore.listSessions()
    }

    private func toggleExpanded(_ session: TapeSessionSummary) async {
        if expandedSessionId == session.sessionId {
            expandedSessionId = nil
            sessionSteps = []
        } else {
            expandedSessionId = session.sessionId
            sessionSteps = (try? await tapeStore.steps(sessionId: session.sessionId)) ?? []
        }
    }

    private func deleteSession(_ session: TapeSessionSummary) async {
        await tapeStore.delete(sessionId: session.sessionId)
        if expandedSessionId == session.sessionId {
            expandedSessionId = nil
            sessionSteps = []
        }
        await loadRecordings()
    }

    /// Restart the interview, replay the recorded session to `throughTurnIndex`
    /// for $0, then go live. Destructive to the current in-progress interview by
    /// design (it starts fresh) — the dev-iteration workflow.
    private func runRestore(sessionId: String, throughUserMessageOrdinal: Int) {
        replayingSessionId = sessionId
        Task {
            await coordinator.restoreFromTape(
                sessionId: sessionId,
                throughUserMessageOrdinal: throughUserMessageOrdinal,
                goLive: true
            )
            replayingSessionId = nil
        }
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
            if tokens.cacheRead > 0 {
                Text("CacheRead:")
                    .foregroundStyle(.tertiary)
                Text(TokenUsageTracker.formatTokenCount(tokens.cacheRead))
            }
            if tokens.cacheCreation > 0 {
                Text("CacheCreate:")
                    .foregroundStyle(.tertiary)
                Text(TokenUsageTracker.formatTokenCount(tokens.cacheCreation))
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
        ToolbarItem(placement: .automatic) {
            Menu {
                Button("Export Events") {
                    exportEventDump()
                }
                Button("Export Conversation Log") {
                    exportConversationLog()
                }
                Button("Export Context Preview") {
                    exportContextPreview()
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
                Task {
                    await loadTodoItems()
                    await loadContextPreview()
                }
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
            Button("Regen Voice Profile") {
                Task {
                    await coordinator.regenerateVoiceProfile()
                }
            }
            .help("Re-extract voice profile from writing samples")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task {
                    isDedupingSkills = true
                    await coordinator.deduplicateSkills()
                    isDedupingSkills = false
                }
            } label: {
                if isDedupingSkills {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Deduping...")
                    }
                } else {
                    Text("Dedupe Skills")
                }
            }
            .disabled(isDedupingSkills)
            .help("Run LLM-powered deduplication on skills")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task {
                    isExpandingATS = true
                    await coordinator.expandATSSkills()
                    isExpandingATS = false
                }
            } label: {
                if isExpandingATS {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Expanding...")
                    }
                } else {
                    Text("ATS Expand Skills")
                }
            }
            .disabled(isExpandingATS)
            .help("Generate ATS synonym variants for skills")
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
            artifacts: coordinator.sessionArtifacts.filter { $0.isDocumentArtifact },
            onConfirm: { selectedIds, operations in
                showRegenDialog = false
                Task {
                    await coordinator.regenerateSelected(
                        artifactIds: selectedIds,
                        regenerateSummary: operations.summary,
                        regenerateSkills: operations.regenerateSkills,
                        regenerateNarrativeCards: operations.regenerateNarrativeCards,
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
        case .processing(.stateChanged(let processing, let statusMessage)):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.stateChanged(\(processing))\(statusInfo)"
        case .llm(.streamingMessageBegan(let id, _, let statusMessage)):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "llm.streamingMessageBegan(id: \(id.uuidString.prefix(8)))\(statusInfo)"
        case .llm(.streamingMessageUpdated(let id, let delta, let statusMessage)):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "llm.streamingMessageUpdated(id: \(id.uuidString.prefix(8)), delta: \(delta.count) chars)\(statusInfo)"
        case .llm(.streamingMessageFinalized(let id, let text, let toolCalls, _)):
            let toolInfo = toolCalls.map { " toolCalls: \($0.count)" } ?? ""
            return "llm.streamingMessageFinalized(id: \(id.uuidString.prefix(8)), text: \(text.count) chars\(toolInfo))"
        case .tool(.callRequested(let call, let statusMessage)):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "tool.callRequested(\(call.name))\(statusInfo)"
        case .objective(.statusChanged(let id, let oldStatus, let newStatus, let phase, _, _, _)):
            return "objective.statusChanged(\(id): \(oldStatus ?? "nil") → \(newStatus), phase: \(phase))"
        case .phase(.transitionApplied(let phase, let timestamp)):
            return "phase.transitionApplied(\(phase), \(timestamp.formatted()))"
        case .timeline(.skeletonReplaced(_, let diff, _)):
            if let diff = diff {
                return "timeline.skeletonReplaced(\(diff.summary))"
            } else {
                return "timeline.skeletonReplaced"
            }
        case .artifact(.knowledgeCardPersisted(let card)):
            return "artifact.knowledgeCardPersisted(title: \(card["title"].stringValue))"
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
            if stats.cacheReadTokens > 0 {
                lines.append("  Cache Reads:     \(TokenUsageTracker.formatTokenCount(stats.cacheReadTokens)) (\(TokenUsageTracker.formatPercentage(stats.cacheHitRate)) hit rate)")
            }
            if stats.cacheCreationTokens > 0 {
                lines.append("  Cache Writes:    \(TokenUsageTracker.formatTokenCount(stats.cacheCreationTokens))")
            }
            if stats.reasoningTokens > 0 {
                lines.append("  Reasoning:       \(TokenUsageTracker.formatTokenCount(stats.reasoningTokens))")
            }
            lines.append("  Requests:        \(stats.requestCount)")
            lines.append("  Session Time:    \(tracker.formattedDuration)")
            lines.append(contentsOf: estimatedCostLines(tracker: tracker))
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
    /// Cost-so-far at live list prices, computed per model from the persisted
    /// price table (refreshed whenever the budget sheet or settings fetch
    /// prices). Omitted entirely when no price table is available.
    private func estimatedCostLines(tracker: TokenUsageTracker) -> [String] {
        guard let persisted = ModelPricing.loadPersistedTable() else { return [] }
        var totalUSD = 0.0
        var unpricedModels: [String] = []
        for (modelId, stats) in tracker.statsByModel {
            guard let price = ModelPricing.price(for: modelId, in: persisted.table) else {
                unpricedModels.append(modelId)
                continue
            }
            totalUSD += ModelPricing.costUSD(
                inputTokens: stats.inputTokens,
                outputTokens: stats.outputTokens,
                cacheReadTokens: stats.cacheReadTokens,
                cacheCreationTokens: stats.cacheCreationTokens,
                at: price
            )
        }
        var lines = [String(format: "  Est. Cost:       $%.2f (list prices as of %@)",
                            totalUSD,
                            persisted.asOf.formatted(date: .abbreviated, time: .shortened))]
        if !unpricedModels.isEmpty {
            lines.append("                   (excludes unpriced: \(unpricedModels.joined(separator: ", ")))")
        }
        return lines
    }

    private func exportEventDump() {
        // Telemetry: emit the session-total token readout alongside the dump.
        coordinator.tokenUsageTracker.logSessionSummary(trigger: "event dump export")
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
                ToastManager.shared.show(.success("Event dump exported successfully"))
            } catch {
                Logger.error("Failed to export event dump: \(error.localizedDescription)", category: .general)
                ToastManager.shared.show(.error("Export failed: \(error.localizedDescription)"))
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
                ToastManager.shared.show(.success("Conversation log exported successfully"))
            } catch {
                Logger.error("Failed to export conversation log: \(error.localizedDescription)", category: .general)
                ToastManager.shared.show(.error("Export failed: \(error.localizedDescription)"))
            }
        }
    }

    private func exportContextPreview() {
        guard let preview = contextPreview else {
            ToastManager.shared.show(.error("No context preview available"))
            return
        }

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "context-preview-\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateSeparator(.dash).dateTimeSeparator(.space).timeSeparator(.colon))).txt"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export Context Preview"
        savePanel.message = "Choose where to save the context preview"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            var output = "Sprung Context Preview\n"
            output += "Generated: \(Date().formatted())\n"
            output += String(repeating: "=", count: 80) + "\n\n"

            // Summary
            output += "SUMMARY\n"
            output += String(repeating: "-", count: 40) + "\n"
            output += "Total Estimated Tokens: \(TokenUsageTracker.formatTokenCount(preview.totalEstimatedTokens))\n"
            output += "Total Bytes: \(formatBytes(preview.totalBytes))\n"
            output += "Tool Count: \(preview.toolCount) (~\(TokenUsageTracker.formatTokenCount(preview.toolSchemaTokens)) tokens)\n"
            output += "Items: \(preview.items.count)\n\n"

            // Items
            output += "CONTEXT ITEMS\n"
            output += String(repeating: "=", count: 80) + "\n\n"

            for (index, item) in preview.items.enumerated() {
                output += "[\(index + 1)] \(item.type.rawValue.uppercased()): \(item.label)\n"
                output += "    Tokens: ~\(TokenUsageTracker.formatTokenCount(item.estimatedTokens)) | Bytes: \(formatBytes(item.byteSize))\n"
                output += String(repeating: "-", count: 40) + "\n"
                output += item.content + "\n"
                output += String(repeating: "=", count: 80) + "\n\n"
            }

            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
                Logger.info("Context preview exported to: \(url.path)", category: .general)
                ToastManager.shared.show(.success("Context preview exported successfully"))
            } catch {
                Logger.error("Failed to export context preview: \(error.localizedDescription)", category: .general)
                ToastManager.shared.show(.error("Export failed: \(error.localizedDescription)"))
            }
        }
    }
}
