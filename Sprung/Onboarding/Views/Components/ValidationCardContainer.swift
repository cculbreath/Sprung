import SwiftUI

/// Reusable container that provides a consistent header with save/cancel controls
/// and surfaces editing callbacks to its child content.
struct ValidationCardContainer<Draft: Equatable, Content: View>: View {
    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    @Binding private var draft: Draft
    private let title: String?
    private let onSave: (Draft) async -> Bool
    private let onCancel: () -> Void
    private let content: (EditableContentCallbacks) -> Content

    @State private var baselineDraft: Draft
    @State private var hasChanges = false
    @State private var saveState: SaveState = .idle
    @State private var editingEntries: Set<UUID> = []

    init(
        draft: Binding<Draft>,
        originalDraft: Draft,
        title: String? = nil,
        onSave: @escaping (Draft) async -> Bool,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping (EditableContentCallbacks) -> Content
    ) {
        _draft = draft
        _baselineDraft = State(initialValue: originalDraft)
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content(callbacks)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            updateDirtyState()
        }
        .onChange(of: draft) { _, _ in
            updateDirtyState()
        }
    }

    private var callbacks: EditableContentCallbacks {
        EditableContentCallbacks(
            isEditing: { id in
                editingEntries.contains(id)
            },
            beginEditing: { id in
                editingEntries.insert(id)
            },
            toggleEditing: { id in
                if editingEntries.contains(id) {
                    editingEntries.remove(id)
                } else {
                    editingEntries.insert(id)
                }
            },
            endEditing: { id in
                editingEntries.remove(id)
            },
            onChange: {
                markDirty()
            }
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 16) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            switch saveState {
            case .saved:
                Text("✅ Changes saved")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .error(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
            case .saving:
                ProgressView()
                    .controlSize(.small)
            case .idle:
                EmptyView()
            }

            Spacer()

            Button("Cancel") {
                cancelChanges()
            }

            Button("Save") {
                handleSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(saveState == .saving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func markDirty() {
        hasChanges = true
        if case .saved = saveState {
            saveState = .idle
        }
    }

    private func updateDirtyState() {
        let dirty = draft != baselineDraft
        if dirty != hasChanges {
            hasChanges = dirty
        }
        if !dirty, case .error = saveState {
            saveState = .idle
        }
    }

    private func handleSave() {
        guard saveState != .saving else { return }
        saveState = .saving

        let currentDraft = draft
        Task {
            let didSave = await onSave(currentDraft)
            await MainActor.run {
                if didSave {
                    baselineDraft = currentDraft
                    hasChanges = false
                    saveState = .saved
                    editingEntries.removeAll()
                } else {
                    saveState = .error("Unable to save changes")
                }
            }
        }
    }

    private func cancelChanges() {
        if hasChanges {
            draft = baselineDraft
            hasChanges = false
            saveState = .idle
            editingEntries.removeAll()
        }
        onCancel()
    }
}
