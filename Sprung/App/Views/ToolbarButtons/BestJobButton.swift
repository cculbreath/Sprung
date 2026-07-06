// Sprung/App/Views/ToolbarButtons/BestJobButton.swift
import SwiftUI

struct BestJobButton: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(DiscoveryCoordinator.self) private var discoveryCoordinator

    @State private var isFlowActive = false
    @State private var isProcessing = false

    var body: some View {
        Button(action: {
            isFlowActive = true
        }, label: {
            if isProcessing {
                Label("Best Job", systemImage: "sparkle").fontWeight(.bold).foregroundColor(.blue)
                    .symbolEffect(.rotate.byLayer)
                    .font(.system(size: 14, weight: .light))
            } else {
                Label("Best Job", systemImage: "medal")
                    .font(.system(size: 14, weight: .light))
            }
        })
        .buttonStyle(.automatic)
        .help("Find the best job matches based on your qualifications")
        .disabled(isProcessing)
        .chooseBestJobsFlow(
            isActive: $isFlowActive,
            isProcessing: $isProcessing,
            dependencies: ChooseBestJobsFlow.Dependencies(
                jobAppStore: jobAppStore,
                knowledgeCardStore: knowledgeCardStore,
                candidateDossierStore: candidateDossierStore,
                coverRefStore: coverRefStore,
                coordinator: discoveryCoordinator
            )
        )
        .onReceive(NotificationCenter.default.publisher(for: .triggerBestJobButton)) { _ in
            isFlowActive = true
        }
    }
}
