import AppKit
import SwiftUI

struct ExperienceEditorView: View {
    @Environment(ExperienceDefaultsStore.self) private var defaultsStore: ExperienceDefaultsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExperienceDefaultsDraft()
    @State private var originalDraft = ExperienceDefaultsDraft()
    @State private var isLoading = true
    @State private var showSectionBrowser = false
    @State private var hasChanges = false
    @State private var saveState: SaveState = .idle
    @State private var editingEntries: Set<UUID> = []

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 1080, minHeight: 780)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await loadDraft()
        }
        .onChange(of: draft) { oldValue, newValue in
            hasChanges = newValue != originalDraft
            if saveState == .saved {
                saveState = .idle
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    showSectionBrowser.toggle()
                }
            } label: {
                Label(showSectionBrowser ? "Hide Sections" : "Enable Sections", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            if case .saved = saveState {
                Text("✅ Changes saved")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if case .error(let message) = saveState {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

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
                        if draft.isWorkEnabled {
                            WorkExperienceSectionView(
                                items: $draft.work,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isVolunteerEnabled {
                            VolunteerExperienceSectionView(
                                items: $draft.volunteer,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isEducationEnabled {
                            EducationExperienceSectionView(
                                items: $draft.education,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isProjectsEnabled {
                            ProjectExperienceSectionView(
                                items: $draft.projects,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isSkillsEnabled {
                            SkillExperienceSectionView(
                                items: $draft.skills,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isAwardsEnabled {
                            AwardExperienceSectionView(
                                items: $draft.awards,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isCertificatesEnabled {
                            CertificateExperienceSectionView(
                                items: $draft.certificates,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isPublicationsEnabled {
                            PublicationExperienceSectionView(
                                items: $draft.publications,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isLanguagesEnabled {
                            LanguageExperienceSectionView(
                                items: $draft.languages,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isInterestsEnabled {
                            InterestExperienceSectionView(
                                items: $draft.interests,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
                        }

                        if draft.isReferencesEnabled {
                            ReferenceExperienceSectionView(
                                items: $draft.references,
                                isEditing: isEditingEntry,
                                beginEditing: beginEditingEntry,
                                toggleEditing: toggleEditingEntry,
                                endEditing: endEditingEntry,
                                onChange: markDirty
                            )
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
