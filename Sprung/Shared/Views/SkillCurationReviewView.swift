//
//  SkillCurationReviewView.swift
//  Sprung
//
//  Review UI for skill bank curation proposals.
//  Shows merge proposals, over-granular flags, category reassignments,
//  and category consolidations. User accepts/rejects per item.
//

import SwiftUI

struct SkillCurationReviewView: View {
    @State var plan: SkillCurationPlan
    let skillStore: SkillStore
    let llmFacade: LLMFacade
    let onDismiss: () -> Void

    private var acceptedCount: Int {
        plan.mergeProposals.filter(\.accepted).count +
        plan.overGranularFlags.filter(\.accepted).count +
        plan.categoryReassignments.filter(\.accepted).count +
        plan.categoryConsolidations.filter(\.accepted).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !plan.mergeProposals.isEmpty {
                        mergeSection
                    }
                    if !plan.overGranularFlags.isEmpty {
                        overGranularSection
                    }
                    if !plan.categoryReassignments.isEmpty {
                        reassignmentSection
                    }
                    if !plan.categoryConsolidations.isEmpty {
                        consolidationSection
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom bar
            bottomBar
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 650)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skill Bank Curation")
                    .font(.title2.weight(.semibold))
                Text("\(plan.totalProposals) proposed changes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
    }

    // MARK: - Merge Proposals

    private var mergeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Merge Proposals (\(plan.mergeProposals.count))", systemImage: "arrow.triangle.merge")
                .font(.headline)

            Text("These skills appear to be duplicates and can be merged.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(plan.mergeProposals.indices, id: \.self) { index in
                mergeProposalRow(index: index)
            }
        }
    }

    private func mergeProposalRow(index: Int) -> some View {
        let proposal = plan.mergeProposals[index]

        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $plan.mergeProposals[index].accepted)
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                // Editable canonical name
                HStack(spacing: 8) {
                    Text("Merge into:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Canonical name", text: $plan.mergeProposals[index].canonicalName)
                        .font(.subheadline.weight(.semibold))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: 250)
                }

                // Skills being merged
                HStack(spacing: 4) {
                    Text("From:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(proposal.mergedSkillNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

                // Rationale
                Text(proposal.rationale)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(10)
        .background(proposal.accepted ? Color.blue.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Over-Granular Flags

    private var overGranularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Over-Granular Skills (\(plan.overGranularFlags.count))", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Text("These skills may be too specific for a resume. Accepting will remove them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(plan.overGranularFlags.indices, id: \.self) { index in
                overGranularRow(index: index)
            }
        }
    }

    private func overGranularRow(index: Int) -> some View {
        let flag = plan.overGranularFlags[index]

        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $plan.overGranularFlags[index].accepted)
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(flag.skillName)
                        .font(.subheadline.weight(.medium))
                    Text(flag.currentCategory)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }

                Text(flag.rationale)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if flag.accepted {
                Text("Remove")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.red)
            } else {
                Text("Keep")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(flag.accepted ? Color.red.opacity(0.03) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Category Reassignments

    private var reassignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Category Reassignments (\(plan.categoryReassignments.count))", systemImage: "arrow.right.arrow.left")
                .font(.headline)

            Text("These skills may be better categorized elsewhere.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(plan.categoryReassignments.indices, id: \.self) { index in
                reassignmentRow(index: index)
            }
        }
    }

    private func reassignmentRow(index: Int) -> some View {
        let reassignment = plan.categoryReassignments[index]

        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $plan.categoryReassignments[index].accepted)
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(reassignment.skillName)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 6) {
                    Text(reassignment.currentCategory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(reassignment.proposedCategory)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }

                Text(reassignment.rationale)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(10)
        .background(reassignment.accepted ? Color.purple.opacity(0.03) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Category Consolidations

    private var consolidationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Category Consolidations (\(plan.categoryConsolidations.count))", systemImage: "rectangle.compress.vertical")
                .font(.headline)

            Text("These categories could be merged for better balance.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(plan.categoryConsolidations.indices, id: \.self) { index in
                consolidationRow(index: index)
            }
        }
    }

    private func consolidationRow(index: Int) -> some View {
        let consolidation = plan.categoryConsolidations[index]

        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $plan.categoryConsolidations[index].accepted)
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(consolidation.fromCategory)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .strikethrough(consolidation.accepted)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(consolidation.toCategory)
                        .font(.subheadline.weight(.medium))
                }

                Text("\(consolidation.affectedSkillCount) skill\(consolidation.affectedSkillCount == 1 ? "" : "s") affected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(consolidation.rationale)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(10)
        .background(consolidation.accepted ? Color.orange.opacity(0.03) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Select all / none
            Button("Select All") {
                selectAll(true)
            }
            .buttonStyle(.bordered)

            Button("Select None") {
                selectAll(false)
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("\(acceptedCount) change\(acceptedCount == 1 ? "" : "s") selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Apply Selected") {
                let service = SkillBankCurationService(skillStore: skillStore, llmFacade: llmFacade)
                service.applyCurationPlan(plan)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(acceptedCount == 0)
        }
        .padding(20)
    }

    private func selectAll(_ selected: Bool) {
        for index in plan.mergeProposals.indices {
            plan.mergeProposals[index].accepted = selected
        }
        for index in plan.overGranularFlags.indices {
            plan.overGranularFlags[index].accepted = selected
        }
        for index in plan.categoryReassignments.indices {
            plan.categoryReassignments[index].accepted = selected
        }
        for index in plan.categoryConsolidations.indices {
            plan.categoryConsolidations[index].accepted = selected
        }
    }
}
