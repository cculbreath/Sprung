import AppKit
import SwiftUI

/// Validation UI for experience defaults, reusing the Experience Editor layout.
/// Allows the user to edit defaults directly, then Confirm or Reject (with notes).
struct ExperienceDefaultsValidationView: View {
    @Environment(ExperienceDefaultsStore.self) private var defaultsStore: ExperienceDefaultsStore

    let coordinator: OnboardingInterviewCoordinator

    @State private var draft = ExperienceDefaultsDraft()
    @State private var originalDraft = ExperienceDefaultsDraft()
    @State private var isLoading = true
    @State private var showSectionBrowser = false
    @State private var saveState: SaveState = .idle
    @State private var editingEntries: Set<UUID> = []
    @State private var rejectionNotes: String = ""

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    private var hasChanges: Bool {
        draft != originalDraft
    }

    private var sectionCallbacks: ExperienceSectionViewCallbacks {
        ExperienceSectionViewCallbacks(
            isEditing: isEditingEntry,
            beginEditing: beginEditingEntry,
            toggleEditing: toggleEditingEntry,
            endEditing: endEditingEntry,
            onChange: markDirty
        )
    }

    private var activeSectionRenderers: [AnyExperienceSectionRenderer] {
        ExperienceSectionRenderers.all.filter { $0.isEnabled(in: draft) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        // This view is often presented inside `ValidationPromptSheet`, which already constrains size.
        // Avoid imposing a larger minimum than the sheet can provide, otherwise content becomes clipped/unusable.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await loadDraft()
        }
        .onChange(of: draft) { _, _ in
            if saveState == .saved {
                saveState = .idle
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    showSectionBrowser.toggle()
                }
            }, label: {
                Label(showSectionBrowser ? "Hide Sections" : "Enable Sections", systemImage: "slider.horizontal.3")
            })
            .buttonStyle(.bordered)

            if case .saved = saveState {
                Text("✅ Saved")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if case .error(let message) = saveState {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if hasChanges {
                Text("Unsaved changes")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button("Reset") {
                resetDraft()
            }
            .disabled(isLoading || !hasChanges)

            Button("Save") {
                Task { _ = await saveDraft() }
            }
            .buttonStyle(.bordered)
            .disabled(isLoading || !hasChanges || saveState == .saving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content
    private var content: some View {
        HStack(spacing: 0) {
            if showSectionBrowser {
                ExperienceSectionBrowserView(draft: $draft)
                    .frame(width: 280)
                    .background(Color(NSColor.controlBackgroundColor))
                    .transition(.move(edge: .leading))
                    .padding(.trailing, 1)
            }
            Divider()
            if isLoading {
                ProgressView("Loading experience defaults…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(activeSectionRenderers) { renderer in
                            renderer.render(in: $draft, callbacks: sectionCallbacks)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showSectionBrowser)
    }

    // MARK: - Footer
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Optional notes (only used if you reject):")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $rejectionNotes)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 74, maxHeight: 110)
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Reject") {
                    Task {
                        await coordinator.submitValidationAndResume(
                            status: "rejected",
                            updatedData: nil,
                            changes: nil,
                            notes: rejectionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil
                                : rejectionNotes
                        )
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Confirm") {
                    Task {
                        if hasChanges {
                            _ = await saveDraft()
                        }
                        await coordinator.submitValidationAndResume(
                            status: hasChanges ? "confirmed_with_changes" : "confirmed",
                            updatedData: await coordinator.currentExperienceDefaultsForValidation(),
                            changes: nil,
                            notes: nil
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || saveState == .saving)
            }
        }
        .padding(20)
    }

    // MARK: - Actions
    private func markDirty() {
        if saveState == .saved {
            saveState = .idle
        }
    }

    @MainActor
    private func loadDraft() async {
        let loadedDraft = defaultsStore.loadDraft()
        draft = loadedDraft
        originalDraft = loadedDraft
        isLoading = false
        clearEditingEntries()
        rejectionNotes = ""
        saveState = .idle
    }

    @MainActor
    private func saveDraft() async -> Bool {
        guard hasChanges else { return true }
        saveState = .saving
        defaultsStore.save(draft: draft)
        originalDraft = draft
        saveState = .saved
        clearEditingEntries()
        return true
    }

    private func resetDraft() {
        draft = originalDraft
        rejectionNotes = ""
        saveState = .idle
        clearEditingEntries()
    }

    private func isEditingEntry(_ id: UUID) -> Bool {
        editingEntries.contains(id)
    }

    private func toggleEditingEntry(_ id: UUID) {
        if editingEntries.contains(id) {
            editingEntries.remove(id)
        } else {
            editingEntries.insert(id)
        }
    }

    private func beginEditingEntry(_ id: UUID) {
        editingEntries.insert(id)
    }

    private func endEditingEntry(_ id: UUID) {
        editingEntries.remove(id)
    }

    private func clearEditingEntries() {
        editingEntries.removeAll()
    }
}
