import SwiftUI

struct TitleSetCurationView: View {
    @Environment(InferenceGuidanceStore.self) private var guidanceStore
    @Bindable var coordinator: OnboardingInterviewCoordinator
    let titleSetService: TitleSetService

    @State private var titleSets: [TitleSet] = []
    @State private var vocabulary: [IdentityTerm] = []
    @State private var selectedSetIds: Set<String> = []
    @State private var isGenerating = false
    @State private var isGeneratingMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Identity Titles")
                .font(.headline)

            Text("Select title sets that resonate with your professional identity. These appear at the top of your resume.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isGenerating {
                ProgressView("Generating title options from your skills...")
                    .padding()
            } else if titleSets.isEmpty {
                Button("Generate Title Options") {
                    Task { await generateInitialTitleSets() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(titleSets) { titleSet in
                            TitleSetCurationRow(
                                titleSet: titleSet,
                                isSelected: selectedSetIds.contains(titleSet.id),
                                onToggle: { toggleSelection(titleSet) },
                                onDelete: { deleteTitleSet(titleSet) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)

                HStack {
                    Button("Generate More") {
                        Task { await generateMoreTitleSets() }
                    }
                    .disabled(isGeneratingMore)

                    Spacer()

                    Button("Save Selected") {
                        saveSelectedSets()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSetIds.isEmpty)
                }

                if isGeneratingMore {
                    ProgressView("Generating more options...")
                        .font(.caption)
                }
            }
        }
        .padding()
        .onAppear {
            loadExistingTitleSets()
        }
    }

    private func loadExistingTitleSets() {
        let existingSets = guidanceStore.titleSets()
        let existingVocabulary = guidanceStore.identityVocabulary()
        if !existingSets.isEmpty || !existingVocabulary.isEmpty {
            titleSets = existingSets
            vocabulary = existingVocabulary
            selectedSetIds = Set(existingSets.filter { $0.isFavorite }.map { $0.id })
        }
    }

    private func generateInitialTitleSets() async {
        isGenerating = true
        defer { isGenerating = false }

        let agentId = await trackTitleSetAgent(
            name: "Title Sets (Initial)",
            status: "Generating title options"
        )

        do {
            let currentSkills: [Skill] = await MainActor.run { coordinator.skillStore.skills }
            let result = try await titleSetService.generateInitialTitleSets(from: currentSkills)

            titleSets = result.titleSets
            vocabulary = result.vocabulary
            selectedSetIds = Set(result.titleSets.filter { $0.isFavorite }.map { $0.id })

            await finalizeTitleSetAgent(
                agentId: agentId,
                summary: "Generated \(result.titleSets.count) title sets"
            )
        } catch {
            Logger.error("🏷️ Title set generation failed: \(error.localizedDescription)", category: .ai)
            await failTitleSetAgent(agentId: agentId, error: error.localizedDescription)
        }
    }

    private func generateMoreTitleSets() async {
        isGeneratingMore = true
        defer { isGeneratingMore = false }

        let agentId = await trackTitleSetAgent(
            name: "Title Sets (More)",
            status: "Generating additional title options"
        )

        do {
            let moreSets = try await titleSetService.generateMoreTitleSets(
                vocabulary: vocabulary,
                existingSets: titleSets,
                count: 5
            )

            titleSets.append(contentsOf: moreSets)
            await finalizeTitleSetAgent(
                agentId: agentId,
                summary: "Generated \(moreSets.count) additional title sets"
            )
        } catch {
            Logger.error("🏷️ Generate more failed: \(error.localizedDescription)", category: .ai)
            await failTitleSetAgent(agentId: agentId, error: error.localizedDescription)
        }
    }

    private func toggleSelection(_ titleSet: TitleSet) {
        if selectedSetIds.contains(titleSet.id) {
            selectedSetIds.remove(titleSet.id)
        } else {
            selectedSetIds.insert(titleSet.id)
        }
    }

    private func deleteTitleSet(_ titleSet: TitleSet) {
        titleSets.removeAll { $0.id == titleSet.id }
        selectedSetIds.remove(titleSet.id)
    }

    private func saveSelectedSets() {
        var updatedSets = titleSets
        for i in updatedSets.indices {
            updatedSets[i].isFavorite = selectedSetIds.contains(updatedSets[i].id)
        }

        Task { @MainActor in
            titleSetService.storeTitleSets(
                vocabulary: vocabulary,
                titleSets: updatedSets,
                in: guidanceStore
            )
            await coordinator.notifyTitleSetsCurated()
        }
    }

    private func trackTitleSetAgent(name: String, status: String) async -> String {
        let tracker = coordinator.agentActivityTracker
        return await MainActor.run {
            let agentId = tracker.trackAgent(
                type: .titleSet,
                name: name,
                task: nil as Task<Void, Never>?
            )
            tracker.updateStatusMessage(agentId: agentId, message: status)
            tracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: status
            )
            return agentId
        }
    }

    private func finalizeTitleSetAgent(agentId: String, summary: String) async {
        await MainActor.run {
            let tracker = coordinator.agentActivityTracker
            tracker.appendTranscript(
                agentId: agentId,
                entryType: .assistant,
                content: summary
            )
            tracker.markCompleted(agentId: agentId)
        }
    }

    private func failTitleSetAgent(agentId: String, error: String) async {
        await MainActor.run {
            coordinator.agentActivityTracker.markFailed(agentId: agentId, error: error)
        }
    }
}

struct TitleSetCurationRow: View {
    let titleSet: TitleSet
    let isSelected: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleSet.displayString)
                    .font(.system(.body, design: .serif))

                HStack(spacing: 4) {
                    Text(titleSet.emphasis.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(emphasisColor.opacity(0.2))
                        .cornerRadius(4)

                    ForEach(titleSet.suggestedFor.prefix(2), id: \.self) { jobType in
                        Text(jobType)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }

    private var emphasisColor: Color {
        switch titleSet.emphasis {
        case .technical: return .blue
        case .research: return .purple
        case .leadership: return .orange
        case .balanced: return .green
        }
    }
}
