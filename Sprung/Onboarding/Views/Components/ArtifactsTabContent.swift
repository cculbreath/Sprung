import SwiftUI
import SwiftData
import SwiftyJSON

/// Tab content showing current interview artifacts and archived artifacts.
struct ArtifactsTabContent: View {
    let coordinator: OnboardingInterviewCoordinator

    /// Current session artifacts (have a session relationship)
    @Query(filter: #Predicate<ArtifactRecord> { $0.session != nil },
           sort: \ArtifactRecord.ingestedAt)
    private var artifacts: [ArtifactRecord]

    /// Archived artifacts (no session, available for reuse)
    @Query(filter: #Predicate<ArtifactRecord> { $0.session == nil },
           sort: \ArtifactRecord.ingestedAt, order: .reverse)
    private var archivedArtifacts: [ArtifactRecord]

    @State private var expandedArtifactIds: Set<UUID> = []
    @State private var artifactToDelete: ArtifactRecord?
    @State private var artifactToDemote: ArtifactRecord?
    @State private var archivedArtifactToDelete: ArtifactRecord?
    @State private var isArchivedSectionExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current Interview Artifacts
            currentArtifactsSection

            // Previously Imported Section (only show if there are archived artifacts)
            if !archivedArtifacts.isEmpty {
                archivedArtifactsSection
            }
        }
        .alert("Delete Artifact?", isPresented: .init(
            get: { artifactToDelete != nil },
            set: { if !$0 { artifactToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                artifactToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let artifact = artifactToDelete {
                    Task {
                        await coordinator.deleteArtifactRecord(id: artifact.id.uuidString)
                    }
                    artifactToDelete = nil
                }
            }
        } message: {
            if let artifact = artifactToDelete {
                Text("Are you sure you want to delete \"\(artifact.displayName)\"? The LLM will be notified that this artifact is no longer available.")
            }
        }
        .alert("Permanently Delete Archived Artifact?", isPresented: .init(
            get: { archivedArtifactToDelete != nil },
            set: { if !$0 { archivedArtifactToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                archivedArtifactToDelete = nil
            }
            Button("Delete Permanently", role: .destructive) {
                if let artifact = archivedArtifactToDelete {
                    Task {
                        await coordinator.deleteArchivedArtifact(id: artifact.id.uuidString)
                    }
                    archivedArtifactToDelete = nil
                }
            }
        } message: {
            if let artifact = archivedArtifactToDelete {
                Text("Are you sure you want to permanently delete \"\(artifact.displayName)\"? This cannot be undone.")
            }
        }
        .alert("Remove from Interview?", isPresented: .init(
            get: { artifactToDemote != nil },
            set: { if !$0 { artifactToDemote = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                artifactToDemote = nil
            }
            Button("Remove", role: .destructive) {
                if let artifact = artifactToDemote {
                    Task {
                        await coordinator.demoteArtifact(id: artifact.id.uuidString)
                    }
                    artifactToDemote = nil
                }
            }
        } message: {
            if let artifact = artifactToDemote {
                Text("Remove \"\(artifact.displayName)\" from this interview? It will be moved to the archive and can be added back later.")
            }
        }
    }

    @ViewBuilder
    private var currentArtifactsSection: some View {
        if artifacts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Interview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(artifacts) { artifact in
                    let pendingSkillsForArtifact = coordinator.skillStore.pendingSkills(forArtifactId: artifact.id.uuidString)
                    ArtifactRow(
                        artifact: artifact,
                        isExpanded: expandedArtifactIds.contains(artifact.id),
                        pendingSkills: pendingSkillsForArtifact,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedArtifactIds.contains(artifact.id) {
                                    expandedArtifactIds.remove(artifact.id)
                                } else {
                                    expandedArtifactIds.insert(artifact.id)
                                }
                            }
                        },
                        onDemote: {
                            artifactToDemote = artifact
                        },
                        onDelete: {
                            artifactToDelete = artifact
                        },
                        onDeleteSkill: { skill in
                            coordinator.skillStore.delete(skill)
                        },
                        onRegenSkills: {
                            Task {
                                await coordinator.regenerateSelected(
                                    artifactIds: [artifact.idString],
                                    regenerateSummary: false,
                                    regenerateSkills: true,
                                    regenerateNarrativeCards: false
                                )
                            }
                        },
                        onRegenNarrativeCards: {
                            Task {
                                await coordinator.regenerateSelected(
                                    artifactIds: [artifact.idString],
                                    regenerateSummary: false,
                                    regenerateSkills: false,
                                    regenerateNarrativeCards: true
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var archivedArtifactsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isArchivedSectionExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isArchivedSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text("Previously Imported")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("(\(archivedArtifacts.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if isArchivedSectionExpanded {
                ForEach(archivedArtifacts) { artifact in
                    ArchivedArtifactRow(
                        artifact: artifact,
                        isExpanded: expandedArtifactIds.contains(artifact.id),
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedArtifactIds.contains(artifact.id) {
                                    expandedArtifactIds.remove(artifact.id)
                                } else {
                                    expandedArtifactIds.insert(artifact.id)
                                }
                            }
                        },
                        onPromote: {
                            Task {
                                await coordinator.promoteArchivedArtifact(id: artifact.id.uuidString)
                            }
                        },
                        onDelete: {
                            archivedArtifactToDelete = artifact
                        }
                    )
                }
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Artifacts",
            systemImage: "doc.text",
            description: Text("Uploaded documents and files will appear here.")
        )
        .frame(height: 180)
    }
}
