import AppKit
import SwiftUI
struct ExperienceEditorView: View {
    @Environment(ExperienceDefaultsStore.self) private var defaultsStore: ExperienceDefaultsStore
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExperienceDefaultsDraft()
    @State private var originalDraft = ExperienceDefaultsDraft()
    @State private var isLoading = true
    @State private var showSectionBrowser = false
    @State private var hasChanges = false
    @State private var saveState: SaveState = .idle
    @State private var editingEntries: Set<UUID> = []
    @State private var showImportSheet = false
    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case error(String)
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
            if !defaultsStore.isSeedCreated {
                seedGenerationBanner
            }
            header
            Divider()
            content
        }
        .frame(minWidth: 1080, minHeight: 780)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await loadDraft()
        }
        .onChange(of: draft) { _, newValue in
            hasChanges = newValue != originalDraft
            if saveState == .saved {
                saveState = .idle
            }
        }
        .onChange(of: defaultsStore.changeVersion) { oldVersion, newVersion in
            // Reload draft when store changes externally (e.g., from SGM apply)
            // Only reload if we don't have unsaved changes
            if !hasChanges && oldVersion != newVersion {
                Task {
                    await loadDraft()
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ExperienceDefaultsImportSheet(
                currentDraft: draft,
                onImport: { imported in
                    draft = imported
                    markDirty()
                }
            )
        }
    }
    // MARK: - Seed Generation Banner

    private var seedGenerationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Generate Experience Defaults")
                    .font(.headline)
                Text("Use AI to generate professional descriptions for your work history, education, and projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .showSeedGeneration, object: nil)
            } label: {
                Label("Generate", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Experience")
                    .font(.headline)
                Text("Manage your work history, education, and skills defaults")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if case .saved = saveState {
                Text("Changes saved")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if case .error(let message) = saveState {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        showSectionBrowser.toggle()
                    }
                } label: {
                    Label(showSectionBrowser ? "Hide Sections" : "Enable Sections", systemImage: "slider.horizontal.3")
                }

                Button {
                    showImportSheet = true
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .disabled(isLoading || appEnvironment.launchState.isReadOnly)
                .help("Import values from an existing resume into Experience Defaults")

                Button("Cancel") {
                    cancelAndClose()
                }
                .disabled(isLoading || hasChanges == false)

                Button("Save") {
                    Task {
                        let didSave = await saveDraft()
                        if didSave {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || hasChanges == false || saveState == .saving)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor))
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
                        // Dynamic sections from section renderers
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

    // MARK: - Actions
    private func markDirty() {
        hasChanges = true
        if saveState == .saved {
            saveState = .idle
        }
    }
    @MainActor
    private func loadDraft() async {
        let loadedDraft = defaultsStore.loadDraft()
        draft = loadedDraft
        originalDraft = loadedDraft
        hasChanges = false
        isLoading = false
        clearEditingEntries()
    }
    @MainActor
    private func saveDraft() async -> Bool {
        guard hasChanges else { return true }
        saveState = .saving
        defaultsStore.save(draft: draft)
        // Mark seed as created when user manually saves content
        defaultsStore.markSeedCreated()
        originalDraft = draft
        hasChanges = false
        saveState = .saved
        clearEditingEntries()
        return true
    }
    private func cancelAndClose() {
        draft = originalDraft
        hasChanges = false
        saveState = .idle
        clearEditingEntries()
        dismiss()
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
