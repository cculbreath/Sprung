import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// ViewModifier to conditionally apply intelligence glow effect when processing,
/// or drop shadow when idle
private struct ConditionalIntelligenceGlow<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let shape: S

    func body(content: Content) -> some View {
        if isActive {
            content.intelligenceOverlay(in: shape)
        } else {
            content.shadow(color: Color.black.opacity(0.18), radius: 20, y: 16)
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

    var body: some View {
        let horizontalPadding: CGFloat = 32
        let topPadding: CGFloat = 28
        let bottomPadding: CGFloat = 28
        let sectionSpacing: CGFloat = 20
        let bannerVisible = !(coordinator.ui.modelAvailabilityMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

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
                    Button {
                        Task {
                            await coordinator.requestCancelLLM()
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        send(state.userInput)
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        state.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            !coordinator.ui.isActive
                    )
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
            }
            .padding(.top, 8)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
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
        .contextMenu { exportTranscriptContextMenu() }
        .onChange(of: coordinator.ui.messages.count, initial: true) { _, newValue in
            handleMessageCountChange(newValue: newValue, proxy: proxy)
        }
        .onChange(of: coordinator.ui.isProcessing) { oldValue, newValue in
            // Track when streaming ends (processing goes from true to false)
            if oldValue == true && newValue == false && isStreamingMessage {
                // LLM message was finalized, scroll to bottom
                isStreamingMessage = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    state.shouldAutoScroll = true
                }
            } else if newValue == true {
                // Processing started, might be streaming
                isStreamingMessage = true
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
                Button {
                    state.shouldAutoScroll = true
                    scrollToLatestMessage(proxy)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }
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

private struct ReasoningStatusBar: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
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
