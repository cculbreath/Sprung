import SwiftUI

/// Writing Samples tab using generic CoverflowBrowser with CoverRefCardView.
struct WritingSamplesBrowserTab: View {
    @Binding var cards: [CoverRef]
    let onCardUpdated: (CoverRef) -> Void
    let onCardDeleted: (CoverRef) -> Void
    let onCardAdded: (CoverRef) -> Void

    @Environment(LLMFacade.self) private var llmFacade
    @Environment(ReasoningStreamState.self) private var reasoningStreamManager
    @Environment(InferenceGuidanceStore.self) private var guidanceStore
    @Environment(CoverRefStore.self) private var coverRefStore

    @State private var selectedFilter: SampleTypeFilter = .all
    @State private var searchText = ""
    @State private var editingCard: CoverRef?
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: CoverRef?
    @State private var showAddSheet = false
    @State private var newCardType: CoverRefType = .writingSample
    @State private var isExtractingVoice = false
    @State private var voiceResultMessage: String?

    enum SampleTypeFilter: String, CaseIterable {
        case all = "All"
        case writingSamples = "Writing Samples"
        case voicePrimers = "Voice Primers"
    }

    /// Writing-sample contents available for voice profile extraction
    /// (voice primers are analysis artifacts, not samples).
    private var writingSampleContents: [String] {
        cards
            .filter { $0.type == .writingSample }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var filteredCards: [CoverRef] {
        var result = cards

        switch selectedFilter {
        case .all: break
        case .writingSamples:
            result = result.filter { $0.type == .writingSample }
        case .voicePrimers:
            result = result.filter { $0.type == .voicePrimer }
        }

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(search) ||
                $0.content.lowercased().contains(search)
            }
        }

        return result
    }

    var body: some View {
        CoverflowBrowser(
            items: .init(
                get: { filteredCards },
                set: { _ in }
            ),
            cardWidth: 520,
            cardHeight: 500,
            accentColor: .blue
        ) { card, isTopCard in
            CoverRefCardView(
                coverRef: card,
                isTopCard: isTopCard,
                onEdit: { editingCard = card },
                onDelete: { cardToDelete = card; showDeleteConfirmation = true }
            )
        } filterContent: { currentIndex in
            filterBar(currentIndex: currentIndex)
        }
        .sheet(item: $editingCard) { card in
            CoverRefEditSheet(
                card: card,
                onSave: { updated in
                    onCardUpdated(updated)
                    editingCard = nil
                },
                onCancel: { editingCard = nil }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            CoverRefEditSheet(
                card: nil,
                defaultType: newCardType,
                onSave: { newCard in
                    onCardAdded(newCard)
                    showAddSheet = false
                },
                onCancel: { showAddSheet = false }
            )
        }
        .alert("Delete Reference?", isPresented: $showDeleteConfirmation, presenting: cardToDelete) { card in
            Button("Delete", role: .destructive) { onCardDeleted(card) }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("Delete \"\(card.name)\"? This cannot be undone.")
        }
        .alert(
            "Voice Profile",
            isPresented: Binding(
                get: { voiceResultMessage != nil },
                set: { if !$0 { voiceResultMessage = nil } }
            )
        ) {
            Button("OK") { voiceResultMessage = nil }
        } message: {
            Text(voiceResultMessage ?? "")
        }
    }

    private func filterBar(currentIndex: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search references...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 280)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(SampleTypeFilter.allCases, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
            }

            Spacer()

            voiceExtractionButton

            Divider()
                .frame(height: 20)

            Button(action: {
                newCardType = .writingSample
                showAddSheet = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Voice Profile Extraction

    private var voiceExtractionButton: some View {
        let sampleCount = writingSampleContents.count
        return Button(action: runVoiceExtraction) {
            HStack(spacing: 4) {
                if isExtractingVoice {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "waveform")
                }
                Text("Analyze Voice")
                if sampleCount > 0 {
                    Text("\(sampleCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.teal.opacity(0.2)))
                }
            }
            .font(.caption)
            .foregroundStyle(.teal)
        }
        .buttonStyle(.plain)
        .disabled(sampleCount == 0 || isExtractingVoice)
        .help(sampleCount == 0
            ? "No writing samples — add or import writing samples first"
            : "Extract a voice profile from \(sampleCount) writing sample\(sampleCount == 1 ? "" : "s")")
    }

    /// Extract a voice profile from the stored writing samples and store it in
    /// the guidance store (same profile the onboarding flow produces — used
    /// for voice anchoring across document analysis and generation).
    private func runVoiceExtraction() {
        let samples = writingSampleContents
        guard !samples.isEmpty else { return }

        isExtractingVoice = true
        Task {
            defer { isExtractingVoice = false }
            do {
                let service = VoiceProfileService(
                    llmFacade: llmFacade,
                    reasoningStreamManager: reasoningStreamManager
                )
                let profile = try await service.extractVoiceProfile(from: samples)
                service.storeVoiceProfile(profile, in: guidanceStore, coverRefStore: coverRefStore)
                voiceResultMessage = voiceProfileSummary(profile, sampleCount: samples.count)
                Logger.info("🎤 Voice profile extracted from writing samples browser (\(samples.count) samples)", category: .ai)
            } catch is ModelConfigurationError {
                NotificationCenter.default.post(name: .showSettings, object: nil)
                voiceResultMessage = "Voice profile model is not configured. Choose one in Settings → Models, then try again."
            } catch {
                voiceResultMessage = "Extraction failed: \(error.localizedDescription)"
                Logger.error("🎤 Writing samples voice extraction failed: \(error.localizedDescription)", category: .ai)
            }
        }
    }

    private func voiceProfileSummary(_ profile: VoiceProfile, sampleCount: Int) -> String {
        var lines = [
            "Extracted from \(sampleCount) writing sample\(sampleCount == 1 ? "" : "s") and stored.",
            "",
            "Enthusiasm: \(profile.enthusiasm.displayName)",
            "Person: \(profile.useFirstPerson ? "first" : "third")",
            "Connectives: \(profile.connectiveStyle)"
        ]
        if let register = profile.vocabularyRegister, !register.isEmpty {
            lines.append("Register: \(register)")
        }
        if let modulation = profile.registerModulation, !modulation.isEmpty {
            lines.append("Modulation: \(modulation)")
        }
        return lines.joined(separator: "\n")
    }

    private func filterChip(_ filter: SampleTypeFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = countFor(filter)

        return Button(action: { selectedFilter = filter }) {
            HStack(spacing: 4) {
                Text(filter.rawValue)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ filter: SampleTypeFilter) -> Int {
        switch filter {
        case .all: return cards.count
        case .writingSamples: return cards.filter { $0.type == .writingSample }.count
        case .voicePrimers: return cards.filter { $0.type == .voicePrimer }.count
        }
    }
}
