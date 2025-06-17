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
    @State private var isExpanded: Bool = true
    @State private var scrollToBottom: Bool = false
    
    // Customizable appearance
    var maxHeight: CGFloat = 200
    var backgroundColor: Color = Color(NSColor.controlBackgroundColor)
    var textColor: Color = .secondary
    
    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                let _ = Logger.debug("🧠 [ReasoningStreamView] Rendering view with text length: \(reasoningText.count)")
                Divider()
                
                VStack(spacing: 0) {
                    // Header bar
                    HStack(spacing: 12) {
                        // Thinking indicator
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                            
                            Text("AI is thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Expand/Collapse button
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "Collapse reasoning" : "Expand reasoning")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(backgroundColor)
                    
                    if isExpanded {
                        Divider()
                        
                        // Reasoning content
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reasoningText)
                                        .font(.caption)
                                        .foregroundColor(textColor)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .id("bottom")
                                }
                            }
                            .frame(maxHeight: maxHeight)
                            .background(backgroundColor.opacity(0.5))
                            .onChange(of: reasoningText) { _ in
                                // Auto-scroll to bottom when new content arrives
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .background(backgroundColor)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
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
    var isStreaming: Bool = false
    
    private var currentTask: Task<Void, Never>?
    
    /// Start processing a reasoning stream
    func startStream<T: AsyncSequence>(_ stream: T) where T.Element == LLMStreamChunk {
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
    
    /// Clear the reasoning text
    func clear() {
        reasoningText = ""
    }
}

// MARK: - Preview

struct ReasoningStreamView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            
            ReasoningStreamView(
                isVisible: .constant(true),
                reasoningText: .constant("""
                Let me analyze this resume to identify areas for improvement...
                
                First, I'll examine the overall structure and formatting. The resume appears to be well-organized with clear sections for education, experience, and skills.
                
                Looking at the experience section, I notice that some bullet points could be more impactful by adding quantifiable achievements. For example, instead of "Managed team projects," it would be stronger to say "Managed 3 cross-functional team projects, delivering all on time and 15% under budget."
                
                The skills section could benefit from being reorganized to highlight the most relevant skills for the target position first...
                """)
            )
        }
        .frame(width: 600, height: 400)
    }
}