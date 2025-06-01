//
//  AiFunctionView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//  Updated by Christopher Culbreath on 5/20/25.
//

import SwiftUI
import AppKit

struct AiFunctionView: View {
    @Binding var res: Resume?
    @State var queryMode: ResumeQueryMode = .normal
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    @AppStorage("openAiApiKey") var openAiKey: String = "none"
    
    // Add state for the query to handle asynchronous loading
    @State private var query: ResumeApiQuery?
    @State private var isLoadingQuery: Bool = false
    @State private var isOptionPressed: Bool = false
    @State private var eventMonitor: Any?

    // Use our unified LLM provider as a State property
    @State private var llmProvider: BaseLLMProvider?
    
    // For TTS functionality - using lazy initialization
    @State private var ttsProvider: OpenAITTSProvider?

    // Flag to determine if this is a new conversation or not
    private let isNewConversation: Bool
    
    // Access to AppState using Swift 6 conventions
    @Environment(\.appState) private var appState

    init(res: Binding<Resume?>, queryMode: ResumeQueryMode = .normal, isNewConversation: Bool = false) {
        _res = res
        _queryMode = State(initialValue: queryMode)
        self.isNewConversation = isNewConversation
        
        if let resume = res.wrappedValue {
            // Clear any existing conversation context for new analysis
            Task { @MainActor in
                resume.clearConversationContext()
            }
        }

        // LLM provider will be initialized in onAppear with proper AppState
        
        // TTS will be initialized in onAppear
    }
    
    // Load the query when the resume changes
    private func loadQuery() {
        guard let myRes = res else { return }
        
        isLoadingQuery = true
        // Use the non-async version which now properly populates applicant data synchronously
        query = myRes.generateQuery()
        // Set the query mode
        query?.queryMode = queryMode
        isLoadingQuery = false
    }

    var body: some View {
        Group {
            if res != nil {
                if let currentQuery = query {
                    AiCommsView(
                        query: currentQuery,
                        res: $res,
                        ttsEnabled: $ttsEnabled,
                        ttsVoice: $ttsVoice
                    )
                } else if isLoadingQuery {
                    ProgressView("Preparing...")
                        .frame(width: 100, height: 30)
                } else {
                    // Show the ai-squiggle button that responds to option-click
                    Button(action: { 
                        // Check for option key
                        if NSEvent.modifierFlags.contains(.option) {
                            queryMode = .withClarifyingQuestions
                        } else {
                            queryMode = .normal
                        }
                        loadQuery() 
                    }) {
                        Image(isOptionPressed ? "ai-squiggle.badge.questionmark" : "ai-squiggle")
                            .renderingMode(.template)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isOptionPressed 
                        ? "Option-click to revise with clarifying questions"
                        : "Generate AI resume revisions")
                    .onAppear {
                        // Monitor for modifier key changes
                        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                            isOptionPressed = event.modifierFlags.contains(.option)
                            return event
                        }
                    }
                    .onDisappear {
                        // Clean up the event monitor
                        if let monitor = eventMonitor {
                            NSEvent.removeMonitor(monitor)
                        }
                    }
                }
            }
            else {
                Text("No Resume Available")
            }
        }
        .onAppear {
            // Properly initialize the client with AppState based on preferred model
            // Initialize LLM provider with app state
            llmProvider = BaseLLMProvider(appState: appState)

            if let myRes = res {
                // Always export the resume when appearing
                myRes.debounceExport()
                // Load the query when appearing
                loadQuery()
            }
        }
        .onChange(of: res) { _, newRes in
            if newRes != nil {
                // Reset query when resume changes
                query = nil
                loadQuery()
            }
        }
    }
}
