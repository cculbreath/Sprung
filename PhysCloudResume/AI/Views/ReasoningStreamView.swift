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
    let modelName: String
    @State private var isExpanded: Bool = true
    @State private var scrollToBottom: Bool = false
    
    // Modal appearance
    var modalWidth: CGFloat = 600
    var modalHeight: CGFloat = 400
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
                    // Header with brain emoji and model name
                    HStack {
                        HStack(spacing: 8) {
                            Text("🧠")
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(modelName) is thinking...")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.8)
                                    
                                    Text("Processing")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Close button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isVisible = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Close reasoning view")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(backgroundColor)
                    
                    Divider()
                    
                    // Reasoning content
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(reasoningText)
                                    .font(.body) // Much larger text
                                    .lineSpacing(4)
                                    .foregroundColor(textColor)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .id("bottom")
                            }
                        }
                        .background(backgroundColor)
                        .onChange(of: reasoningText) { _ in
                            // Auto-scroll to bottom when new content arrives
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(width: modalWidth, height: modalHeight)
                .background(backgroundColor)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
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
    var modelName: String = "" {
        didSet {
            Logger.debug("🧠 [ReasoningStreamManager] modelName changed to: \(modelName)")
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
                """),
                modelName: "claude-3.5-sonnet"
            )
        }
        .frame(width: 600, height: 400)
    }
}