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
    // Live SwiftData query to automatically refresh on model changes
    @Query(sort: \CoverRef.name) private var allCoverRefs: [CoverRef]
    @Binding var includeResumeRefs: Bool
    @Binding var selectedBackgroundFacts: Set<String>
    @Binding var selectedWritingSamples: Set<String>
    @State private var showAddSheet = false
    @State private var newRefType: CoverRefType = .backgroundFact
    @State private var showBrowser = false
    var showGroupBox: Bool = true
    private var backgroundFacts: [CoverRef] {
        allCoverRefs.filter { $0.type == .backgroundFact }
    }
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
            // Include Resume Background toggle
            Toggle("Include Resume Background", isOn: $includeResumeRefs)
                .toggleStyle(.checkbox)

            // Browse All button
            Button(action: { showBrowser = true }) {
                HStack {
                    Image(systemName: "rectangle.stack")
                    Text("Browse All References")
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

            // Background Facts Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Background Facts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        newRefType = .backgroundFact
                        showAddSheet = true
                    }, label: {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.accentColor)
                    })
                    .buttonStyle(.plain)
                }
                if backgroundFacts.isEmpty {
                    Text("No background facts added yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(backgroundFacts, id: \.id) { ref in
                        CheckableRefRow(
                            ref: ref,
                            isSelected: selectedBackgroundFacts.contains(ref.id.description),
                            onToggle: { isSelected in
                                if isSelected {
                                    selectedBackgroundFacts.insert(ref.id.description)
                                } else {
                                    selectedBackgroundFacts.remove(ref.id.description)
                                }
                            },
                            onDelete: {
                                deleteRef(ref)
                            }
                        )
                    }
                }
            }
            // Writing Samples Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Writing Samples")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        newRefType = .writingSample
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
                refType: newRefType,
                onAdd: { name, content in
                    addNewRef(name: name, content: content, type: newRefType)
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
        // Remove from selections
        selectedBackgroundFacts.remove(ref.id.description)
        selectedWritingSamples.remove(ref.id.description)
        // Delete from store
        coverRefStore.deleteCoverRef(ref)
    }
    private func addNewRef(name: String, content: String, type: CoverRefType) {
        let newRef = CoverRef(
            name: name,
            content: content,
            enabledByDefault: false,
            type: type
        )
        coverRefStore.addCoverRef(newRef)
        // Auto-select the new ref
        if type == .backgroundFact {
            selectedBackgroundFacts.insert(newRef.id.description)
        } else {
            selectedWritingSamples.insert(newRef.id.description)
        }
    }
}
// MARK: - Add Cover Ref Sheet
struct AddCoverRefSheet: View {
    let refType: CoverRefType
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
            .navigationTitle("Add \(refType == .backgroundFact ? "Background Fact" : "Writing Sample")")
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
