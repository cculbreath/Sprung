import AppKit
import SwiftUI
import UniformTypeIdentifiers
/// ViewModifier to conditionally apply intelligence glow effect when processing,
/// or drop shadow when idle. Uses opacity transitions to preserve scroll position.
private struct ConditionalIntelligenceGlow<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let shape: S
    func body(content: Content) -> some View {
        // Always apply both effects with opacity control to preserve view identity
        // and prevent scroll position reset when toggling states
        content
            .shadow(
                color: Color.black.opacity(isActive ? 0 : 0.18),
                radius: 20,
                y: 16
            )
            .overlay {
                shape.intelligenceStroke()
                    .opacity(isActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: isActive)
            }
    }
}
struct OnboardingInterviewChatPanel: View {
    let coordinator: OnboardingInterviewCoordinator
    @Bindable var state: OnboardingInterviewViewModel
    let modelStatusDescription: String
    let onOpenSettings: () -> Void
    @State private var showScrollToLatest = false
    @State private var exportErrorMessage: String?
    @State private var lastMessageCount: Int = 0
    @State private var composerHeight: CGFloat = ChatComposerTextView.minimumHeight
    @State private var isStreamingMessage = false
    @State private var showMessageFailedAlert = false
    @State private var lastStreamingContentLength: Int = 0
    @State private var reasoningDismissTime: Date?
    @State private var reasoningStreamStartLength: Int = 0
    @State private var reasoningTimerTick: Int = 0
    private let horizontalPadding: CGFloat = 32
    private let topPadding: CGFloat = 28
    private let bottomPadding: CGFloat = 28
    private let sectionSpacing: CGFloat = 20

    private var bannerVisible: Bool {
        !(coordinator.ui.modelAvailabilityMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var isWaitingForValidation: Bool {
        coordinator.pendingValidationPrompt?.mode == .validation
    }

    private var isSendDisabled: Bool {
        state.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !coordinator.ui.isActive ||
            isWaitingForValidation
    }

    var body: some View {
        return VStack(spacing: 0) {
            if bannerVisible, let alert = coordinator.ui.modelAvailabilityMessage {
                ModelAvailabilityBanner(
                    text: alert,
                    onOpenSettings: onOpenSettings,
                    onDismiss: {
                        coordinator.clearModelAvailabilityMessage()
                    }
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollViewReader { proxy in
                messageScrollView(proxy: proxy)
            }
            .padding(.top, bannerVisible ? 8 : topPadding)
            .padding(.horizontal, horizontalPadding)
            // Note: Next questions feature removed during event-driven migration
            Divider()
                .padding(.top, sectionSpacing)
                .padding(.horizontal, horizontalPadding)
            // Note: Reasoning summary display removed during event-driven migration
            HStack(alignment: .top, spacing: 12) {
                ChatComposerTextView(
                    text: Binding(
                        get: { state.userInput },
                        set: { state.userInput = $0 }
                    ),
                    isEditable: coordinator.ui.isActive,
                    onSubmit: { text in
                        send(text)
                    },
                    measuredHeight: $composerHeight
                )
                .frame(height: min(max(composerHeight, 44), 140))
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                )
                if coordinator.ui.isProcessing {
                    Button(action: {
                        Task {
                            await coordinator.requestCancelLLM()
                        }
                    }, label: {
                        Label("Stop", systemImage: "stop.fill")
                    })
                    .buttonStyle(.bordered)
                } else {
                    Button(action: {
                        send(state.userInput)
                    }, label: {
                        Label("Send", systemImage: "paperplane.fill")
                    })
                    .buttonStyle(.borderedProminent)
                    .disabled(isSendDisabled)
                    .help(isWaitingForValidation ? "Submit or cancel the validation dialog to continue" : "")
                }
            }
            .padding(.top, sectionSpacing)
            .padding(.horizontal, horizontalPadding)
            HStack(spacing: 6) {
                Text(modelStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Change in Settings…") {
                    onOpenSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
                Spacer()
                // Extraction indicator (non-blocking - chat remains enabled)
                if coordinator.ui.isExtractionInProgress {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(coordinator.ui.extractionStatusMessage ?? "Extracting...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
            .animation(.easeInOut(duration: 0.2), value: coordinator.ui.isExtractionInProgress)
        }
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        // .animation(.easeInOut(duration: 0.2), value: coordinator.latestReasoningSummary)
        .animation(.easeInOut(duration: 0.2), value: coordinator.ui.modelAvailabilityMessage)
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { _ in exportErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert("Message Failed to Send", isPresented: $showMessageFailedAlert) {
            Button("OK", role: .cancel) {
                coordinator.ui.clearFailedMessage()
            }
        } message: {
            Text(coordinator.ui.failedMessageError ?? "The message could not be sent. Please try again.")
        }
        .onChange(of: coordinator.ui.failedMessageText) { _, newValue in
            // When a message fails, restore the text to the input box and show alert
            if let text = newValue {
                state.userInput = text
                showMessageFailedAlert = true
            }
        }
    }
    private func messageScrollView(proxy: ScrollViewProxy) -> some View {
        let bubbleShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(coordinator.ui.messages.filter { !$0.isSystemGenerated }) { message in
                    MessageBubble(message: message)
                        .id(message.id)
                }
                // Add invisible spacer at the bottom for smooth scrolling
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .padding(20)
        }
        .textSelection(.enabled)
        .background(bubbleShape.fill(.thinMaterial))
        .clipShape(bubbleShape)
        .modifier(ConditionalIntelligenceGlow(isActive: coordinator.ui.isProcessing, shape: bubbleShape))
        .overlay(alignment: .bottomTrailing) {
            scrollToLatestButton(proxy: proxy)
        }
        .overlay(scrollOffsetOverlay())
        .overlay {
            reasoningSummaryOverlay
        }
        .contextMenu { exportTranscriptContextMenu() }
        .onChange(of: coordinator.ui.messages.count, initial: true) { _, newValue in
            handleMessageCountChange(newValue: newValue, proxy: proxy)
        }
        .onChange(of: coordinator.ui.isProcessing) { oldValue, newValue in
            // Track when streaming ends (processing goes from true to false)
            if oldValue == true && newValue == false && isStreamingMessage {
                // LLM message was finalized, scroll to bottom
                isStreamingMessage = false
                lastStreamingContentLength = 0
                resetReasoningOverlayState()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    state.shouldAutoScroll = true
                }
            } else if oldValue == false && newValue == true {
                // Processing started - scroll to bottom if auto-scroll is enabled
                isStreamingMessage = true
                lastStreamingContentLength = 0
                if state.shouldAutoScroll {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        // Track streaming message content changes for auto-scroll during streaming
        .onChange(of: streamingMessageContentLength) { oldLength, newLength in
            // Start reasoning dismiss timer when streaming begins
            if oldLength == 0 && newLength > 0 {
                startReasoningDismissTimer()
            }
            // Only auto-scroll if streaming and user hasn't scrolled away
            if isStreamingMessage && state.shouldAutoScroll && newLength > lastStreamingContentLength {
                lastStreamingContentLength = newLength
                // Scroll to bottom on content updates
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .onAppear {
            lastMessageCount = coordinator.ui.messages.count
            scrollToLatestMessage(proxy)
        }
    }
    private func scrollToLatestButton(proxy: ScrollViewProxy) -> some View {
        Group {
            if showScrollToLatest {
                Button(action: {
                    state.shouldAutoScroll = true
                    scrollToLatestMessage(proxy)
                }, label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                })
                .buttonStyle(.plain)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
                .shadow(radius: 3, y: 2)
            }
        }
    }
    private func scrollOffsetOverlay() -> some View {
        ScrollViewOffsetObserver { offset, maxOffset in
            let nearBottom = max(maxOffset - offset, 0) < 32
            if state.shouldAutoScroll != nearBottom {
                state.shouldAutoScroll = nearBottom
            }
            updateScrollToLatestVisibility(isNearBottom: nearBottom)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
    private func handleMessageCountChange(newValue: Int, proxy: ScrollViewProxy) {
        defer { lastMessageCount = newValue }
        guard newValue > lastMessageCount else { return }
        // Check if this is a user message (not streaming)
        // User messages are added when not processing, or at the start of processing
        if !coordinator.ui.isProcessing || !isStreamingMessage {
            // This is likely a user message, scroll to bottom
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                // Re-enable auto-scroll when we scroll to bottom after a new message
                state.shouldAutoScroll = true
            }
        }
        // For streaming messages, we'll scroll when processing ends (handled in onChange of isProcessingSync)
    }
    private func exportTranscriptContextMenu() -> some View {
        Button("Export Transcript…") {
            exportTranscript()
        }
    }
    private func updateScrollToLatestVisibility(isNearBottom: Bool) {
        let shouldShow = !isNearBottom
        guard showScrollToLatest != shouldShow else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            showScrollToLatest = shouldShow
        }
    }
    private func send(_ text: String) {
        guard coordinator.ui.isProcessing == false else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.shouldAutoScroll = true
        state.userInput = ""
        Task {
            await coordinator.sendChatMessage(trimmed)
        }
    }
    private func scrollToLatestMessage(_ proxy: ScrollViewProxy) {
        guard state.shouldAutoScroll else { return }
        // Use the "bottom" anchor we added for more reliable scrolling
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    /// Track the content length of the last assistant message for streaming scroll updates
    private var streamingMessageContentLength: Int {
        guard let lastMessage = coordinator.ui.messages.last,
              lastMessage.role == .assistant else {
            return 0
        }
        return lastMessage.text.count
    }

    /// Show reasoning summary at top of chat while model is thinking.
    /// Holds for 7s after streaming starts or until response would occlude overlay, whichever is shorter.
    @ViewBuilder
    private var reasoningSummaryOverlay: some View {
        let summary = coordinator.chatTranscriptStore.currentReasoningSummarySync
        let isActive = coordinator.chatTranscriptStore.isReasoningActiveSync
        let hasContent = !(summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        // Dismiss conditions when streaming (use reasoningTimerTick to trigger re-evaluation):
        // 1. 7 seconds elapsed since streaming started
        // 2. Response has grown significantly (would be occluded by overlay ~200 chars)
        let _ = reasoningTimerTick // Force view update on timer tick
        let isStreaming = streamingMessageContentLength > 0
        let timedOut = reasoningDismissTime.map { Date() > $0 } ?? false
        let responseGrownLarge = isStreaming && (streamingMessageContentLength - reasoningStreamStartLength) > 200

        let shouldShow = hasContent && !timedOut && !responseGrownLarge

        if shouldShow, let text = summary {
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Thinking")
                                .font(.headline)
                            if isActive {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(6)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(20)
                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Start the 7-second dismiss timer when streaming begins
    private func startReasoningDismissTimer() {
        guard reasoningDismissTime == nil else { return }
        reasoningStreamStartLength = streamingMessageContentLength
        reasoningDismissTime = Date().addingTimeInterval(7)
        // Schedule a view update after 7 seconds to trigger dismissal
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            reasoningTimerTick += 1
        }
    }

    /// Reset reasoning overlay state when streaming ends
    private func resetReasoningOverlayState() {
        reasoningDismissTime = nil
        reasoningStreamStartLength = 0
    }
    private func exportTranscript() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultTranscriptFilename()
        panel.allowedContentTypes = [UTType.plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let transcript = coordinator.transcriptExportString()
            do {
                try transcript.write(to: url, atomically: true, encoding: .utf8)
                Logger.info("📝 Transcript exported to \(url.path)", category: .ai)
            } catch {
                Logger.error("Transcript export failed: \(error.localizedDescription)", category: .ai)
                DispatchQueue.main.async {
                    exportErrorMessage = "Could not save transcript. \(error.localizedDescription)"
                }
            }
        }
    }
    private func defaultTranscriptFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let stamp = formatter.string(from: Date())
        return "Sprung Transcript \(stamp).txt"
    }
}
private struct ModelAvailabilityBanner: View {
    let text: String
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            Button("Change in Settings…") {
                onOpenSettings()
            }
            .buttonStyle(.link)
            Button(action: {
                onDismiss()
            }, label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            })
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }
}
private struct ScrollViewOffsetObserver: NSViewRepresentable {
    typealias NSViewType = NSView
    var onScroll: (CGFloat, CGFloat) -> Void
    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: nsView)
        }
        context.coordinator.onScroll = onScroll
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.invalidate()
    }
    final class Coordinator: NSObject {
        var onScroll: (CGFloat, CGFloat) -> Void
        private var observation: NSKeyValueObservation?
        private weak var scrollView: NSScrollView?
        init(onScroll: @escaping (CGFloat, CGFloat) -> Void) {
            self.onScroll = onScroll
        }
        func attachIfNeeded(from view: NSView) {
            guard let scrollView = view.enclosingScrollView else { return }
            if scrollView === self.scrollView { return }
            attach(to: scrollView)
        }
        private func attach(to scrollView: NSScrollView) {
            observation?.invalidate()
            self.scrollView = scrollView
            observation = scrollView.contentView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                self?.notify()
            }
            notify()
        }
        private func notify() {
            guard let scrollView else { return }
            let offset = scrollView.contentView.bounds.origin.y
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            let visibleHeight = scrollView.contentView.bounds.height
            let maxOffset = max(documentHeight - visibleHeight, 0)
            DispatchQueue.main.async {
                self.onScroll(offset, maxOffset)
            }
        }
        func invalidate() {
            observation?.invalidate()
            observation = nil
            scrollView = nil
        }
    }
}
