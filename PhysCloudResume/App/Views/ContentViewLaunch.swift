// PhysCloudResume/App/Views/ContentViewLaunch.swift

import SwiftUI
import SwiftData

struct ContentViewLaunch: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    // Create DragInfo instance here
    @State private var dragInfo = DragInfo() // Use @State for Observable objects owned by the view

    var body: some View {
        // Initialise all stores once per scene.
        let resStore = ResStore(context: modelContext)
        let resRefStore = ResRefStore(context: modelContext)
        let coverRefStore = CoverRefStore(context: modelContext)
        let coverLetterStore = CoverLetterStore(context: modelContext, refStore: coverRefStore)
        let jobAppStore = JobAppStore(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
        let resModelStore = ResModelStore(context: modelContext, resStore: resStore)

        // Inject all stores AND DragInfo into the environment
        return ContentView()
            .environment(jobAppStore)
            .environment(resRefStore)
            .environment(resModelStore)
            .environment(resStore)
            .environment(coverRefStore)
            .environment(coverLetterStore)
            .environment(dragInfo) // Inject DragInfo here
            .background(AppKitToolbarSetup())
            .onAppear {
                // Check and migrate database if needed
                DatabaseMigrationHelper.checkAndMigrateIfNeeded(modelContext: modelContext)
                
                // Initialize LLMService with ModelContext
                LLMService.shared.initialize(appState: appState, modelContext: modelContext)
                
                // Force reconfiguration to ensure API key is picked up
                LLMService.shared.reconfigureClient()
            }
        // Note: AppState is already injected via .environment(appState) in PhysicsCloudResumeApp
    }
}
