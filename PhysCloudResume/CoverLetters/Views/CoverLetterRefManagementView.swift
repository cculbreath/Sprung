//
//  CoverLetterRefManagementView.swift
//  PhysCloudResume
//
//  Created on 6/2/25.
//

import SwiftUI
import SwiftData

/// A compact view for managing cover letter references (background facts and writing samples)
/// Designed to be embedded in toolbar or popover
struct CoverLetterRefManagementView: View {
    @Environment(CoverRefStore.self) var coverRefStore: CoverRefStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore
    @Environment(\.modelContext) private var modelContext
    
    // Live SwiftData query to automatically refresh on model changes
    @Query(sort: \CoverRef.name) private var allCoverRefs: [CoverRef]
    
    @State private var selectedRefIds: Set<String> = []
    @State private var showAddMenu = false
    @State private var newRefName = ""
    @State private var newRefContent = ""
    @State private var newRefType: CoverRefType = .backgroundFact
    @State private var showAddSheet = false
    
    private var backgroundFacts: [CoverRef] {
        allCoverRefs.filter { $0.type == .backgroundFact }
    }
    
    private var writingSamples: [CoverRef] {
        allCoverRefs.filter { $0.type == .writingSample }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and add button
            HStack {
                Text("Cover Letter References")
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    Button {
                        newRefType = .backgroundFact
                        showAddSheet = true
                    } label: {
                        Label("Add Background Fact", systemImage: "doc.text")
                    }
                    
                    Button {
                        newRefType = .writingSample
                        showAddSheet = true
                    } label: {
                        Label("Add Writing Sample", systemImage: "text.quote")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            
            if let letter = coverLetterStore.cL {
                // Include Resume Background toggle
                Toggle("Include Resume Background", isOn: includeResumeBinding(for: letter))
                    .toggleStyle(.checkbox)
                
                Divider()
                
                // Background Facts Section
                if !backgroundFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Background Facts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ForEach(backgroundFacts) { ref in
                            RefCheckboxRow(
                                ref: ref,
                                letter: letter,
                                isSelected: letter.enabledRefs.contains { $0.id == ref.id },
                                onToggle: { isSelected in
                                    toggleRef(ref, for: letter, isSelected: isSelected)
                                },
                                onDelete: {
                                    deleteRef(ref)
                                }
                            )
                        }
                    }
                }
                
                // Writing Samples Section
                if !writingSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing Samples")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ForEach(writingSamples) { ref in
                            RefCheckboxRow(
                                ref: ref,
                                letter: letter,
                                isSelected: letter.enabledRefs.contains { $0.id == ref.id },
                                onToggle: { isSelected in
                                    toggleRef(ref, for: letter, isSelected: isSelected)
                                },
                                onDelete: {
                                    deleteRef(ref)
                                }
                            )
                        }
                    }
                }
                
                if allCoverRefs.isEmpty {
                    Text("No references added yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                Text("No cover letter selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .frame(width: 350)
        .sheet(isPresented: $showAddSheet) {
            AddRefSheet(
                refType: newRefType,
                onAdd: { name, content in
                    addNewRef(name: name, content: content, type: newRefType)
                }
            )
        }
    }
    
    private func includeResumeBinding(for letter: CoverLetter) -> Binding<Bool> {
        Binding<Bool>(
            get: { letter.includeResumeRefs },
            set: { newValue in
                guard let oldCL = coverLetterStore.cL else { return }
                if oldCL.generated {
                    // If it's generated, create a new copy with updated value
                    let newCL = coverLetterStore.createDuplicate(letter: oldCL)
                    newCL.includeResumeRefs = newValue
                    newCL.generated = false
                    coverLetterStore.cL = newCL
                } else {
                    // Otherwise, just mutate the existing letter
                    letter.includeResumeRefs = newValue
                }
            }
        )
    }
    
    private func toggleRef(_ ref: CoverRef, for letter: CoverLetter, isSelected: Bool) {
        guard let oldCL = coverLetterStore.cL else { return }
        
        if oldCL.generated {
            // If it's generated, create a new copy
            let newCL = coverLetterStore.createDuplicate(letter: oldCL)
            var newEnabledRefs = newCL.enabledRefs
            if isSelected {
                // Add the ref if it's not already there
                if !newEnabledRefs.contains(where: { $0.id == ref.id }) {
                    newEnabledRefs.append(ref)
                }
            } else {
                // Remove the ref
                newEnabledRefs.removeAll { $0.id == ref.id }
            }
            newCL.enabledRefs = newEnabledRefs
            newCL.generated = false
            coverLetterStore.cL = newCL
        } else {
            // Otherwise, just mutate the existing letter
            var enabledRefs = letter.enabledRefs
            if isSelected {
                // Add the ref if it's not already there
                if !enabledRefs.contains(where: { $0.id == ref.id }) {
                    enabledRefs.append(ref)
                }
            } else {
                // Remove the ref
                enabledRefs.removeAll { $0.id == ref.id }
            }
            letter.enabledRefs = enabledRefs
        }
    }
    
    private func deleteRef(_ ref: CoverRef) {
        // Remove from all cover letters
        if let letter = coverLetterStore.cL {
            var enabledRefs = letter.enabledRefs
            enabledRefs.removeAll { $0.id == ref.id }
            letter.enabledRefs = enabledRefs
        }
        
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
    }
}

/// A row showing a checkbox for a cover letter reference with delete capability
struct RefCheckboxRow: View {
    let ref: CoverRef
    let letter: CoverLetter
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { onToggle($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.name)
                        .font(.body)
                        .lineLimit(1)
                    
                    if !ref.content.isEmpty {
                        Text(ref.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .toggleStyle(.checkbox)
            
            Spacer()
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
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

/// Sheet for adding a new reference
struct AddRefSheet: View {
    let refType: CoverRefType
    let onAdd: (String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var content = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Reference Details") {
                    TextField("Name", text: $name)
                    
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(refType == .backgroundFact ? "New Background Fact" : "New Writing Sample")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        onAdd(name, content)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}