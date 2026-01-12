import SwiftUI

struct TitleSetCurationView: View {
    @Environment(InferenceGuidanceStore.self) private var guidanceStore
    @Bindable var coordinator: OnboardingInterviewCoordinator
    let titleSetService: TitleSetService

    @State private var titleSets: [TitleSet] = []
    @State private var selectedSetIds: Set<String> = []
    @State private var isGenerating = false
    @State private var isGeneratingMore = false
    @State private var isSaving = false
    @State private var isGeneratingCustom = false
    @State private var customTitleInput: String = ""
    @State private var showCustomTitleField = false
    @State private var isGeneratingWithGuidance = false
    @State private var guidanceComment: String = ""
    @State private var showGuidanceField = false

    /// Access to the full skill bank for context
    private var skills: [Skill] {
        coordinator.skillStore.skills
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Identity Titles")
                .font(.headline)

            Text("Select title sets that resonate with your professional identity. These appear at the top of your resume.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isGenerating {
                VStack {
                    ProgressView("Generating title options from your skills...")
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if titleSets.isEmpty {
                VStack {
                    Button("Generate Title Options") {
                        Task { await generateInitialTitleSets() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
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

                // Custom title input
                if showCustomTitleField {
                    HStack {
                        TextField("Enter a title (e.g., Software Architect)", text: $customTitleInput)
                            .textFieldStyle(.roundedBorder)

                        Button("Generate") {
                            Task { await generateWithCustomTitle() }
                        }
                        .disabled(customTitleInput.trimmingCharacters(in: .whitespaces).isEmpty || isGeneratingCustom)

                        Button {
                            showCustomTitleField = false
                            customTitleInput = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if isGeneratingCustom {
                        ProgressView("Generating sets with \"\(customTitleInput)\"...")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Guidance comment input
                if showGuidanceField {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Generation Guidance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showGuidanceField = false
                                guidanceComment = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        TextField(
                            "e.g., Include 'Physicist', avoid 'Analyst', focus on leadership...",
                            text: $guidanceComment,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                        HStack {
                            Spacer()
                            Button("Generate with Guidance") {
                                Task { await generateWithGuidance() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(guidanceComment.trimmingCharacters(in: .whitespaces).isEmpty || isGeneratingWithGuidance)
                        }

                        if isGeneratingWithGuidance {
                            ProgressView("Generating sets with your guidance...")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }

                HStack {
                    Button("Generate More") {
                        Task { await generateMoreTitleSets() }
                    }
                    .disabled(isGeneratingMore || isSaving || isGeneratingCustom || isGeneratingWithGuidance)

                    Button("Specify Title") {
                        showCustomTitleField.toggle()
                        if showCustomTitleField { showGuidanceField = false }
                    }
                    .disabled(isGeneratingMore || isSaving || isGeneratingCustom || isGeneratingWithGuidance)

                    Button("With Comment") {
                        showGuidanceField.toggle()
                        if showGuidanceField { showCustomTitleField = false }
                    }
                    .disabled(isGeneratingMore || isSaving || isGeneratingCustom || isGeneratingWithGuidance)

                    Spacer()

                    Button(isSaving ? "Saving..." : "Save & Continue") {
                        Task { await saveSelectedSets() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSetIds.isEmpty || isSaving || isGeneratingMore || isGeneratingCustom || isGeneratingWithGuidance)
                }

                if selectedSetIds.isEmpty && !titleSets.isEmpty {
                    Text("Select at least one title set to continue")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if isGeneratingMore {
                    ProgressView("Generating more options...")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
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
        if !existingSets.isEmpty {
            titleSets = existingSets
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

        let favoritedSets = titleSets.filter { selectedSetIds.contains($0.id) }

        do {
            let moreSets = try await titleSetService.generateMoreTitleSets(
                skills: skills,
                existingSets: titleSets,
                favoritedSets: favoritedSets
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

    private func generateWithCustomTitle() async {
        let specifiedTitle = customTitleInput.trimmingCharacters(in: .whitespaces)
        guard !specifiedTitle.isEmpty else { return }

        isGeneratingCustom = true
        defer { isGeneratingCustom = false }

        let agentId = await trackTitleSetAgent(
            name: "Title Sets (Custom: \(specifiedTitle))",
            status: "Generating sets with \"\(specifiedTitle)\""
        )

        do {
            let customSets = try await titleSetService.generateWithSpecifiedTitle(
                specifiedTitle: specifiedTitle,
                skills: skills,
                existingSets: titleSets
            )

            titleSets.append(contentsOf: customSets)

            // Clear input and hide field on success
            customTitleInput = ""
            showCustomTitleField = false

            await finalizeTitleSetAgent(
                agentId: agentId,
                summary: "Generated \(customSets.count) sets with \"\(specifiedTitle)\""
            )
        } catch {
            Logger.error("🏷️ Custom title generation failed: \(error.localizedDescription)", category: .ai)
            await failTitleSetAgent(agentId: agentId, error: error.localizedDescription)
        }
    }

    private func generateWithGuidance() async {
        let guidance = guidanceComment.trimmingCharacters(in: .whitespaces)
        guard !guidance.isEmpty else { return }

        isGeneratingWithGuidance = true
        defer { isGeneratingWithGuidance = false }

        let agentId = await trackTitleSetAgent(
            name: "Title Sets (Guided)",
            status: "Generating sets with guidance"
        )

        let favoritedSets = titleSets.filter { selectedSetIds.contains($0.id) }

        do {
            let guidedSets = try await titleSetService.generateWithGuidance(
                guidance: guidance,
                skills: skills,
                existingSets: titleSets,
                favoritedSets: favoritedSets
            )

            titleSets.append(contentsOf: guidedSets)

            // Clear input and hide field on success
            guidanceComment = ""
            showGuidanceField = false

            await finalizeTitleSetAgent(
                agentId: agentId,
                summary: "Generated \(guidedSets.count) sets with guidance: \(guidance.prefix(30))..."
            )
        } catch {
            Logger.error("🏷️ Guided generation failed: \(error.localizedDescription)", category: .ai)
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

    private func saveSelectedSets() async {
        isSaving = true
        defer { isSaving = false }

        // Only persist the approved/selected title sets
        let approvedSets = titleSets
            .filter { selectedSetIds.contains($0.id) }
            .map { set in
                var approved = set
                approved.isFavorite = true  // All approved sets are favorites
                return approved
            }

        Logger.info("🏷️ Persisting \(approvedSets.count) approved title sets to inference guidance", category: .ai)

        titleSetService.storeTitleSets(
            titleSets: approvedSets,
            in: guidanceStore
        )

        Logger.info("🏷️ Title sets persisted to guidance store, dismissing curation UI", category: .ai)

        // Mark curation complete and dismiss the UI
        coordinator.ui.titleSetsCurated = true
        coordinator.ui.shouldGenerateTitleSets = false

        // Sync to SessionUIState for tool gating (unlocks generate_experience_defaults)
        await coordinator.state.setTitleSetsCurated(true)

        // Notify the LLM with the approved sets so it can choose the best one
        await coordinator.notifyTitleSetsCurated(approvedSets: approvedSets)
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
