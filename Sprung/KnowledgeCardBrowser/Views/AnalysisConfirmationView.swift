//
//  AnalysisConfirmationView.swift
//  Sprung
//
//  View for reviewing and confirming card proposals before generation.
//  Shows new cards to create and existing cards that will be enhanced.
//

import SwiftUI

struct AnalysisConfirmationView: View {
    let result: StandaloneKCCoordinator.AnalysisResult
    let coordinator: StandaloneKCCoordinator
    let onConfirm: ([KnowledgeCard], [(proposal: KnowledgeCard, existing: KnowledgeCard)]) -> Void
    let onCancel: () -> Void

    @State private var selectedNewCards: Set<UUID>
    @State private var selectedEnhancements: Set<UUID>
    @State private var isGenerating = false

    init(
        result: StandaloneKCCoordinator.AnalysisResult,
        coordinator: StandaloneKCCoordinator,
        onConfirm: @escaping ([KnowledgeCard], [(proposal: KnowledgeCard, existing: KnowledgeCard)]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.result = result
        self.coordinator = coordinator
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // Select all by default
        _selectedNewCards = State(initialValue: Set(result.newCards.map(\.id)))
        _selectedEnhancements = State(initialValue: Set(result.enhancements.map(\.proposal.id)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isGenerating {
                    generatingProgressView
                } else if result.newCards.isEmpty && result.enhancements.isEmpty {
                    emptyStateView
                } else {
                    List {
                        if !result.newCards.isEmpty {
                            Section("Create New Cards (\(result.newCards.count))") {
                                ForEach(result.newCards) { card in
                                    Toggle(isOn: binding(for: card.id, in: $selectedNewCards)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(card.title)
                                                .font(.headline)
                                            HStack {
                                                cardTypeBadge(card.cardType?.rawValue ?? "other")
                                                if !card.extractable.scale.isEmpty {
                                                    Text("\(card.extractable.scale.count) outcomes")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }

                        if !result.enhancements.isEmpty {
                            Section("Enhance Existing Cards (\(result.enhancements.count))") {
                                ForEach(result.enhancements, id: \.proposal.id) { item in
                                    Toggle(isOn: binding(for: item.proposal.id, in: $selectedEnhancements)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.existing.title)
                                                .font(.headline)
                                            Text("Add evidence from new documents")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }

                        if !result.skillBank.skills.isEmpty {
                            Section("Skills to Add (\(result.skillBank.skills.count))") {
                                let grouped = result.skillBank.groupedByCategory()
                                let sortedCats = SkillCategoryUtils.sortedCategories(from: result.skillBank.skills)
                                ForEach(sortedCats, id: \.self) { category in
                                    if let skills = grouped[category], !skills.isEmpty {
                                        HStack {
                                            Image(systemName: SkillCategoryUtils.icon(for: category))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 20)
                                            Text(category)
                                                .font(.subheadline)
                                            Spacer()
                                            Text("\(skills.count)")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                footerView
            }
            .navigationTitle("Analysis Results")
            .frame(width: 500, height: 450)
        }
    }

    private var generatingProgressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(coordinator.status.displayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Cards Found",
            systemImage: "doc.questionmark",
            description: Text("The analysis didn't find any new cards to create or existing cards to enhance.")
        )
    }

    private func cardTypeBadge(_ cardType: String) -> some View {
        Text(cardType.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(cardTypeColor(cardType).opacity(0.2))
            .foregroundStyle(cardTypeColor(cardType))
            .clipShape(Capsule())
    }

    private func cardTypeColor(_ cardType: String) -> Color {
        switch cardType.lowercased() {
        case "employment", "job":
            return .blue
        case "project":
            return .green
        case "skill":
            return .purple
        case "education":
            return .orange
        case "achievement":
            return .yellow
        default:
            return .gray
        }
    }

    private var footerView: some View {
        HStack {
            if isGenerating {
                Text(coordinator.status.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                let skillCount = result.skillBank.skills.count
                let skillText = skillCount > 0 ? " + \(skillCount) skills" : ""
                Text("\(selectedCount) selected\(skillText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(isGenerating)

            Button("Generate") {
                isGenerating = true
                let newCards = result.newCards.filter { selectedNewCards.contains($0.id) }
                let enhancements = result.enhancements.filter { selectedEnhancements.contains($0.proposal.id) }
                onConfirm(newCards, enhancements)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || (selectedNewCards.isEmpty && selectedEnhancements.isEmpty))
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var selectedCount: Int {
        selectedNewCards.count + selectedEnhancements.count
    }

    private func binding(for cardId: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(cardId) },
            set: { isSelected in
                if isSelected {
                    set.wrappedValue.insert(cardId)
                } else {
                    set.wrappedValue.remove(cardId)
                }
            }
        )
    }
}
