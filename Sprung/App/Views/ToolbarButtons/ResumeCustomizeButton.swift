// Sprung/App/Views/ToolbarButtons/ResumeCustomizeButton.swift
import SwiftUI
struct ResumeCustomizeButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var selectedTab: TabList
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .triggerCustomizeButton)) { _ in
                guard jobAppStore.selectedApp?.selectedRes != nil else { return }
                NotificationCenter.default.post(name: .polishResume, object: nil)
            }
    }
}
