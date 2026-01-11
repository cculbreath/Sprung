import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Scrolling message list view with auto-scroll and export
struct OnboardingChatMessageList: View {
    let coordinator: OnboardingInterviewCoordinator
    @Binding var shouldAutoScroll: Bool
    let onExportError: (String) -> Void

    @State private var showScrollToLatest = false
    @State private var lastMessageCount: Int = 0
    @State private var isStreamingMessage = false
    @State private var lastStreamingContentLength: Int = 0

    private let bubbleShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    /// Sent messages (not queued) - shown in chronological order
    private var sentMessages: [OnboardingMessage] {
        let queuedIds = coordinator.ui.queuedMessageIds
        return coordinator.ui.messages.filter {
            !$0.isSystemGenerated &&
            !($0.role == .assistant && $0.text.isEmpty) &&
            !queuedIds.contains($0.id)
        }
    }

    /// Queued messages - shown at bottom with special styling
    private var queuedMessages: [OnboardingMessage] {
        let queuedIds = coordinator.ui.queuedMessageIds
        return coordinator.ui.messages.filter {
            queuedIds.contains($0.id) && !$0.isSystemGenerated
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Sent messages in chronological order
                    ForEach(sentMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Queued messages section (at bottom with dimmed styling)
                    if !queuedMessages.isEmpty {
                        Divider()
                            .padding(.vertical, 8)

                        ForEach(queuedMessages) { message in
                            QueuedMessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    // Add invisible spacer at the bottom for smooth scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(14)
            }
            .textSelection(.enabled)
            .background(bubbleShape.fill(.thinMaterial))
            .clipShape(bubbleShape)
            .modifier(ConditionalIntelligenceGlow(isActive: coordinator.ui.isStreaming, shape: bubbleShape))
            .overlay(alignment: .bottomTrailing) {
                scrollToLatestButton(proxy: proxy)
            }
            .overlay(scrollOffsetOverlay())
            .contextMenu { exportTranscriptContextMenu() }
            .onChange(of: coordinator.ui.messages.count, initial: true) { _, newValue in
                handleMessageCountChange(newValue: newValue, proxy: proxy)
            }
            .onChange(of: coordinator.ui.isStreaming) { oldValue, newValue in
                // Track when streaming ends (isStreaming goes from true to false)
                if oldValue == true && newValue == false && isStreamingMessage {
                    // LLM message was finalized, scroll to bottom
                    isStreamingMessage = false
                    lastStreamingContentLength = 0
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        shouldAutoScroll = true
                    }
                } else if oldValue == false && newValue == true {
                    // Streaming started - scroll to bottom if auto-scroll is enabled
                    isStreamingMessage = true
                    lastStreamingContentLength = 0
                    if shouldAutoScroll {
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
                // Only auto-scroll if streaming and user hasn't scrolled away
                if isStreamingMessage && shouldAutoScroll && newLength > lastStreamingContentLength {
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
    }

    private func scrollToLatestButton(proxy: ScrollViewProxy) -> some View {
        Group {
            if showScrollToLatest {
                Button(action: {
                    shouldAutoScroll = true
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
            if shouldAutoScroll != nearBottom {
                shouldAutoScroll = nearBottom
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
        // User messages are added when not streaming, or at the start of streaming
        if !coordinator.ui.isStreaming || !isStreamingMessage {
            // This is likely a user message, scroll to bottom
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                // Re-enable auto-scroll when we scroll to bottom after a new message
                shouldAutoScroll = true
            }
        }
        // For streaming messages, we'll scroll when streaming ends (handled in onChange of isStreaming)
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

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy) {
        guard shouldAutoScroll else { return }
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
                    onExportError("Could not save transcript. \(error.localizedDescription)")
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

/// Message bubble for queued messages - dimmed styling with clock icon
private struct QueuedMessageBubble: View {
    let message: OnboardingMessage

    var body: some View {
        HStack {
            Spacer()
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(Color.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(0.6)
        }
    }
}
