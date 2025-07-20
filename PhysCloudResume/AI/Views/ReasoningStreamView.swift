//
//  ReasoningStreamView.swift
//  PhysCloudResume
//
//  Displays real-time reasoning tokens from AI models in a collapsible bottom bar
//

import SwiftUI

struct ReasoningStreamView: View {
    @Binding var isVisible: Bool
    @Binding var reasoningText: String
    @Binding var isStreaming: Bool
    let modelName: String
    @State private var isExpanded: Bool = true
    @State private var scrollToBottom: Bool = false
    
    // Modal appearance
    var modalWidth: CGFloat = 700
    var modalHeight: CGFloat = 500
    var backgroundColor: Color = Color(NSColor.windowBackgroundColor)
    var textColor: Color = .primary
    
    var body: some View {
        ZStack {
            if isVisible {
                let _ = Logger.debug("🧠 [ReasoningStreamView] Rendering modal with text length: \(reasoningText.count)")
                
                // Semi-transparent backdrop
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isVisible = false
                        }
                    }
                
                // Modal content
                VStack(spacing: 0) {
                    // Header with gradient background
                    ZStack {
                        // Gradient background
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.15),
                                Color.purple.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        HStack {
                            // Brain emoji with subtle animation
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: 70, height: 70)
                                    .shadow(color: .blue.opacity(0.2), radius: 8, x: 0, y: 4)
                                
                                Text("🧠")
                                    .font(.system(size: 48))
                                    .rotationEffect(.degrees(-10))
                            }
                            .padding(.leading, 8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(modelName)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                        .overlay(
                                            Circle()
                                                .fill(Color.green.opacity(0.3))
                                                .frame(width: 16, height: 16)
                                                .scaleEffect(isStreaming ? 1.5 : 1)
                                                .opacity(isStreaming ? 0 : 1)
                                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: isStreaming)
                                        )
                                    
                                    Text("Reasoning in progress...")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.leading, 12)
                            
                            Spacer()
                            
                            // Close button with hover effect
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isVisible = false
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Close reasoning view")
                            .padding(.trailing, 8)
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 100)
                    
                    // Divider with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.gray.opacity(0.1),
                                    Color.gray.opacity(0.2),
                                    Color.gray.opacity(0.1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                    
                    // Reasoning content with improved styling
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if reasoningText.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "brain")
                                            .font(.system(size: 40))
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .symbolEffect(.pulse)
                                        
                                        Text("AI is thinking...")
                                            .font(.system(.body, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        let _ = Logger.debug("🧠 [ReasoningStreamView] Rendering reasoning text - first 200 chars: \(reasoningText.prefix(200))")
                                        
                                        // Use Text view with basic markdown parsing
                                        Text(parseBasicMarkdown(reasoningText))
                                            .font(.system(.body, design: .default))
                                            .foregroundColor(.primary)
                                            .textSelection(.enabled)
                                            .multilineTextAlignment(.leading)
                                    }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 20)
                                        .id("bottom")
                                    
                                    // Subtle typing indicator at bottom
                                    if isStreaming {
                                        HStack(spacing: 4) {
                                            ForEach(0..<3) { index in
                                                Circle()
                                                    .fill(Color.blue.opacity(0.6))
                                                    .frame(width: 6, height: 6)
                                                    .scaleEffect(isStreaming ? 1.2 : 0.8)
                                                    .animation(
                                                        .easeInOut(duration: 0.6)
                                                        .repeatForever()
                                                        .delay(Double(index) * 0.2),
                                                        value: isStreaming
                                                    )
                                            }
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.bottom, 16)
                                    }
                                }
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .onChange(of: reasoningText) {
                            // Auto-scroll to bottom when new content arrives
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(width: modalWidth, height: modalHeight)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
            }
        }
    }
    
    // MARK: - Markdown Parsing
    
    /// Parse basic markdown for bold text (**text**)
    private func parseBasicMarkdown(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Find all **bold** patterns
        let pattern = "\\*\\*([^*]+)\\*\\*"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            // Process matches in reverse order to maintain correct ranges
            for match in matches.reversed() {
                if let range = Range(match.range, in: text),
                   let attributedRange = Range(range, in: attributedString) {
                    // Get the text without asterisks (capture group 1)
                    if let contentRange = Range(match.range(at: 1), in: text) {
                        let boldText = String(text[contentRange])
                        
                        // Replace the entire match with just the bold text
                        attributedString.replaceSubrange(attributedRange, with: AttributedString(boldText))
                        
                        // Apply bold formatting to the replacement
                        if let newRange = attributedString.range(of: boldText, options: [], locale: nil) {
                            attributedString[newRange].font = .system(.body, design: .default).bold()
                        }
                    }
                }
            }
        } catch {
            // If regex fails, return plain text
            Logger.debug("Failed to parse markdown: \(error)")
        }
        
        return attributedString
    }
}

// MARK: - Reasoning Stream Manager

/// Manages the reasoning stream state and text accumulation
@MainActor
@Observable
class ReasoningStreamManager {
    var isVisible: Bool = false {
        didSet {
            Logger.debug("🧠 [ReasoningStreamManager] isVisible changed to: \(isVisible)")
        }
    }
    var reasoningText: String = "" {
        didSet {
            Logger.debug("🧠 [ReasoningStreamManager] reasoningText updated, length: \(reasoningText.count)")
        }
    }
    var modelName: String = "" {
        didSet {
            Logger.debug("🧠 [ReasoningStreamManager] modelName changed to: \(modelName)")
        }
    }
    var isStreaming: Bool = false
    
    private var currentTask: Task<Void, Never>?
    
    /// Start processing a reasoning stream
    func startStream<T: AsyncSequence>(_ stream: T) where T.Element == LLMStreamChunk, T: Sendable, T.AsyncIterator: Sendable {
        // Cancel any existing stream
        currentTask?.cancel()
        
        // Reset state
        reasoningText = ""
        isVisible = true
        isStreaming = true
        
        currentTask = Task {
            do {
                for try await chunk in stream {
                    // Check for cancellation
                    if Task.isCancelled { break }
                    
                    // Append reasoning content
                    if let reasoning = chunk.reasoningContent {
                        Logger.debug("🧠 [ReasoningStreamManager] Appending reasoning: \(reasoning.prefix(100))...")
                        reasoningText += reasoning
                    }
                    
                    // Check if finished
                    if chunk.isFinished {
                        isStreaming = false
                    }
                }
            } catch {
                Logger.error("🚨 Error in reasoning stream: \(error)")
                isStreaming = false
            }
        }
    }
    
    /// Stop the current stream
    func stopStream() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
    }
    
    /// Hide the reasoning view
    func hide() {
        isVisible = false
    }
    
    /// Clear all reasoning state
    func clear() {
        reasoningText = ""
        modelName = ""
    }
    
    /// Start a new reasoning session with model information
    func startReasoning(modelName: String) {
        self.modelName = modelName
        self.reasoningText = ""
        self.isVisible = true
        self.isStreaming = true
    }
}
