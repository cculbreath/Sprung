import SwiftUI

/// Sheet for refining a single knowledge card with AI.
/// Collects refinement instructions and model selection, then runs the LLM call.
struct KCRefinementSheet: View {
    let card: KnowledgeCard
    let onComplete: () -> Void
    let onCancel: () -> Void

    @Environment(LLMFacade.self) private var llmFacade

    @State private var instructions: String = ""
    @State private var selectedModel: String = ""
    @State private var isRefining = false
    @State private var errorMessage: String?

    private var canRefine: Bool {
        !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedModel.isEmpty
            && !isRefining
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cardPreviewSection
                    instructionsSection
                    modelSection
                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 520, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Restore last-used model
            if let saved = UserDefaults.standard.string(forKey: "kcRefinementModelId"), !saved.isEmpty {
                selectedModel = saved
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Refine Knowledge Card")
                    .font(.title2.weight(.semibold))
                Text(card.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var cardPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current Card", systemImage: "doc.text")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                if let type = card.cardType {
                    Label(type.displayName, systemImage: type.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let org = card.organization, !org.isEmpty {
                    Label(org, systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(card.narrative.prefix(200)) + (card.narrative.count > 200 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refinement Instructions")
                .font(.headline)
                .foregroundStyle(.primary)

            TextEditor(text: $instructions)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text("e.g., Expand the narrative with more quantified outcomes and technical depth...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var modelSection: some View {
        DropdownModelPicker(
            selectedModel: $selectedModel,
            requiredCapability: .structuredOutput,
            title: "Model"
        )
    }

    private func errorSection(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footerSection: some View {
        HStack {
            if isRefining {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refining...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .disabled(isRefining)

            Button("Refine", action: runRefinement)
                .buttonStyle(.borderedProminent)
                .disabled(!canRefine)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(20)
    }

    // MARK: - Actions

    private func runRefinement() {
        errorMessage = nil
        isRefining = true

        // Persist model selection
        UserDefaults.standard.set(selectedModel, forKey: "kcRefinementModelId")

        Task {
            do {
                let service = KCRefinementService(llmFacade: llmFacade)
                let refined = try await service.refine(
                    card: card,
                    instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                    modelId: selectedModel
                )
                service.apply(refined, to: card)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
                isRefining = false
            }
        }
    }
}
