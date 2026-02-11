//
//  CoverRefSelectionManagerView.swift
//  Sprung
//
//  Created on 6/9/25.
//
import SwiftUI
import SwiftData
/// A reusable view for managing cover letter reference selections
/// Used in both Generate Cover Letter and Batch Generate Cover Letter sheets
struct CoverRefSelectionManagerView: View {
    @Environment(CoverRefStore.self) var coverRefStore: CoverRefStore
    @Environment(KnowledgeCardStore.self) var knowledgeCardStore: KnowledgeCardStore
    // Live SwiftData query to automatically refresh on model changes
    @Query(sort: \CoverRef.name) private var allCoverRefs: [CoverRef]
    @Binding var knowledgeCardInclusion: KnowledgeCardInclusion
    @Binding var selectedKnowledgeCardIds: Set<String>
    @Binding var selectedWritingSamples: Set<String>
    @State private var showAddSheet = false
    @State private var showBrowser = false
    var showGroupBox: Bool = true
    private var writingSamples: [CoverRef] {
        allCoverRefs.filter { $0.type == .writingSample }
    }
    var body: some View {
        if showGroupBox {
            GroupBox("Source Management") {
                content
            }
        } else {
            content
        }
    }
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Knowledge Cards inclusion picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Knowledge Cards")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Picker("Knowledge Cards", selection: $knowledgeCardInclusion) {
                    ForEach(KnowledgeCardInclusion.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Show individual card selection when "Selected" is chosen
                if knowledgeCardInclusion == .selected {
                    let cards = knowledgeCardStore.knowledgeCards
                    if cards.isEmpty {
                        Text("No knowledge cards available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(cards, id: \.id) { card in
                                KnowledgeCardCheckRow(
                                    card: card,
                                    isSelected: selectedKnowledgeCardIds.contains(card.id.uuidString),
                                    onToggle: { isSelected in
                                        if isSelected {
                                            selectedKnowledgeCardIds.insert(card.id.uuidString)
                                        } else {
                                            selectedKnowledgeCardIds.remove(card.id.uuidString)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            // Browse All button
            Button(action: { showBrowser = true }) {
                HStack {
                    Image(systemName: "rectangle.stack")
                    Text("Browse Writing References")
                    Spacer()
                    Text("\(allCoverRefs.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(.bordered)
            // Writing Samples Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Writing Samples")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        showAddSheet = true
                    }, label: {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.accentColor)
                    })
                    .buttonStyle(.plain)
                }
                if writingSamples.isEmpty {
                    Text("No writing samples added yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(writingSamples) { ref in
                        CheckableRefRow(
                            ref: ref,
                            isSelected: selectedWritingSamples.contains(ref.id.description),
                            onToggle: { isSelected in
                                if isSelected {
                                    selectedWritingSamples.insert(ref.id.description)
                                } else {
                                    selectedWritingSamples.remove(ref.id.description)
                                }
                            },
                            onDelete: {
                                deleteRef(ref)
                            }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCoverRefSheet(
                onAdd: { name, content in
                    addNewRef(name: name, content: content)
                }
            )
        }
        .sheet(isPresented: $showBrowser) {
            WritingSamplesBrowserTab(
                cards: .init(
                    get: { allCoverRefs },
                    set: { _ in }
                ),
                onCardUpdated: { _ in
                    // SwiftData will auto-refresh via @Query
                },
                onCardDeleted: { card in
                    deleteRef(card)
                },
                onCardAdded: { card in
                    coverRefStore.addCoverRef(card)
                }
            )
            .frame(width: 720, height: 680)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    private func deleteRef(_ ref: CoverRef) {
        selectedWritingSamples.remove(ref.id.description)
        coverRefStore.deleteCoverRef(ref)
    }
    private func addNewRef(name: String, content: String) {
        let newRef = CoverRef(
            name: name,
            content: content,
            enabledByDefault: false,
            type: .writingSample
        )
        coverRefStore.addCoverRef(newRef)
        selectedWritingSamples.insert(newRef.id.description)
    }
}
/// A row showing a checkable knowledge card
struct KnowledgeCardCheckRow: View {
    let card: KnowledgeCard
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: {
            onToggle(!isSelected)
        }, label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let type = card.cardType {
                        Text(type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        })
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(isHovering ? 0.1 : 0))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
// MARK: - Add Cover Ref Sheet
struct AddCoverRefSheet: View {
    let onAdd: (String, String) -> Void
    @State private var name = ""
    @State private var content = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.headline)
                    TextField("Enter name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content")
                        .font(.headline)
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(minHeight: 200)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Add Writing Sample")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name, content)
                        dismiss()
                    }
                    .disabled(name.isEmpty || content.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}
