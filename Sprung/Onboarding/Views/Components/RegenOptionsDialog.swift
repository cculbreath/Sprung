//
//  RegenOptionsDialog.swift
//  Sprung
//
//  Dialog for selecting artifacts and operations for regeneration.
//

import SwiftUI

struct RegenOptionsDialog: View {
    let artifacts: [ArtifactRecord]
    let onConfirm: (Set<String>, RegenOperations) -> Void
    let onCancel: () -> Void

    struct RegenOperations {
        var summary: Bool = true
        var knowledgeExtraction: Bool = true
        var remerge: Bool = true
        var dedupeNarratives: Bool = false
    }

    @State private var selectedArtifactIds: Set<String> = []
    @State private var operations = RegenOperations()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Regenerate Artifacts")
                .font(.headline)

            // Artifact selection
            GroupBox("Select Artifacts") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button("Select All") {
                            selectedArtifactIds = Set(artifacts.map { $0.idString })
                        }
                        .buttonStyle(.link)
                        Button("Select None") {
                            selectedArtifactIds.removeAll()
                        }
                        .buttonStyle(.link)
                        Spacer()
                        Text("\(selectedArtifactIds.count) selected")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(.bottom, 4)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(artifacts, id: \.idString) { artifact in
                                RegenArtifactRow(
                                    artifact: artifact,
                                    isSelected: selectedArtifactIds.contains(artifact.idString),
                                    onToggle: { toggleArtifact(artifact) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .padding(8)
            }

            // Operations
            GroupBox("Operations (per selected artifact)") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Regenerate Summary", isOn: $operations.summary)
                    Toggle("Regenerate Knowledge Extraction", isOn: $operations.knowledgeExtraction)
                }
                .padding(8)
            }

            // Global options
            GroupBox("After Completion") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Run Card Merge", isOn: $operations.remerge)
                    Toggle("Dedupe Narratives", isOn: $operations.dedupeNarratives)
                        .help("Run LLM-powered deduplication on narrative cards after merge")
                }
                .padding(8)
            }

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Regenerate") {
                    onConfirm(selectedArtifactIds, operations)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedArtifactIds.isEmpty || (!operations.summary && !operations.knowledgeExtraction))
            }
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            // Default to all artifacts selected
            selectedArtifactIds = Set(artifacts.map { $0.idString })
        }
    }

    private func toggleArtifact(_ artifact: ArtifactRecord) {
        if selectedArtifactIds.contains(artifact.idString) {
            selectedArtifactIds.remove(artifact.idString)
        } else {
            selectedArtifactIds.insert(artifact.idString)
        }
    }

    struct RegenArtifactRow: View {
        let artifact: ArtifactRecord
        let isSelected: Bool
        let onToggle: () -> Void

        var body: some View {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .onTapGesture { onToggle() }

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.filename)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if artifact.summary != nil {
                            Label("Summary", systemImage: "doc.text")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if artifact.hasKnowledgeExtraction {
                            Label("Knowledge", systemImage: "rectangle.stack")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        Text("\(artifact.extractedContent.count) chars")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }
        }
    }
}
