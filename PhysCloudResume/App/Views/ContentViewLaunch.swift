// PhysCloudResume/App/Views/ContentViewLaunch.swift

import SwiftUI
import SwiftData

struct ContentViewLaunch: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var deps: AppDependencies?

    var body: some View {
        Group {
            if let deps {
                ContentView()
                    .environment(deps.jobAppStore)
                    .environment(deps.resRefStore)
                    .environment(deps.resModelStore)
                    .environment(deps.resStore)
                    .environment(deps.coverRefStore)
                    .environment(deps.coverLetterStore)
                    .environment(deps.enabledLLMStore)
                    .environment(deps.dragInfo)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if deps == nil {
                deps = AppDependencies(modelContext: modelContext)
            }
        }
        // Note: AppState is already injected via .environment(appState) in PhysicsCloudResumeApp
    }
}
