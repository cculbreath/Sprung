//
//  ProjectCurationView.swift
//  Sprung
//
//  View for approving/rejecting project proposals.
//

import SwiftUI

/// View for curating discovered project proposals
struct ProjectCurationView: View {
    let proposals: [ProjectProposal]
    let onApprove: (ProjectProposal) -> Void
    let onReject: (ProjectProposal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            proposalsList
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project Proposals")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Review and approve projects to include on your resume. Approved projects will have detailed descriptions generated.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Proposals List

    private var proposalsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(proposals) { proposal in
                    ProjectProposalCard(
                        proposal: proposal,
                        onApprove: { onApprove(proposal) },
                        onReject: { onReject(proposal) }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Project Proposal Card

private struct ProjectProposalCard: View {
    let proposal: ProjectProposal
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            descriptionText
            rationaleText
            sourceTag
            actionButtons
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(statusBorder)
    }

    private var headerRow: some View {
        HStack {
            Text(proposal.name)
                .font(.headline)

            Spacer()

            if proposal.isApproved {
                approvedBadge
            }
        }
    }

    private var descriptionText: some View {
        Text(proposal.description)
            .font(.body)
            .foregroundStyle(.secondary)
    }

    private var rationaleText: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text(proposal.rationale)
                .font(.callout)
                .italic()
        }
        .padding(8)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var sourceTag: some View {
        HStack {
            Image(systemName: sourceIcon)
                .font(.caption)
            Text(sourceLabel)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private var sourceIcon: String {
        switch proposal.sourceType {
        case .timeline: return "clock"
        case .knowledgeCard: return "square.stack.3d.up"
        case .skillBank: return "list.bullet"
        case .llmProposed: return "sparkles"
        }
    }

    private var sourceLabel: String {
        switch proposal.sourceType {
        case .timeline: return "From Timeline"
        case .knowledgeCard: return "From Knowledge Card"
        case .skillBank: return "Inferred from Skills"
        case .llmProposed: return "AI Suggested"
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if !proposal.isApproved {
            HStack(spacing: 12) {
                Button {
                    onApprove()
                } label: {
                    Label("Include", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    onReject()
                } label: {
                    Label("Skip", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var approvedBadge: some View {
        Text("Included")
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
    }

    private var cardBackground: some ShapeStyle {
        Color(.controlBackgroundColor)
    }

    @ViewBuilder
    private var statusBorder: some View {
        if proposal.isApproved {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.green.opacity(0.5), lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
