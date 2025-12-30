import SwiftUI

/// Tab content showing knowledge cards summary and browser access.
struct KnowledgeTabContent: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var showBrowser = false

    private var allCards: [ResRef] {
        coordinator.allKnowledgeCards
    }

    private var planItems: [KnowledgeCardPlanItem] {
        coordinator.ui.knowledgeCardPlan
    }

    private var resRefStore: ResRefStore {
        coordinator.getResRefStore()
    }

    private var documentationGaps: [MergedCardInventory.DocumentationGap] {
        coordinator.ui.mergedInventory?.gaps ?? []
    }

    var body: some View {
        VStack(spacing: 16) {
            // Summary card
            summaryCard

            // Open browser button
            Button(action: { showBrowser = true }) {
                HStack {
                    Image(systemName: "rectangle.stack")
                    Text("Browse All Cards")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Onboarding progress (if in interview)
            if !planItems.isEmpty {
                onboardingProgressSection
            }

            // Documentation gaps (if any)
            if !documentationGaps.isEmpty {
                documentationGapsSection
            }
        }
        .sheet(isPresented: $showBrowser) {
            KnowledgeCardBrowserOverlay(
                isPresented: $showBrowser,
                cards: .init(
                    get: { allCards },
                    set: { _ in }
                ),
                resRefStore: resRefStore,
                onCardUpdated: { card in
                    resRefStore.updateResRef(card)
                },
                onCardDeleted: { card in
                    resRefStore.deleteResRef(card)
                },
                onCardAdded: { card in
                    resRefStore.addResRef(card)
                }
            )
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.purple)
                Text("Knowledge Cards")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            HStack(spacing: 16) {
                statItem(count: allCards.count, label: "Total")
                statItem(
                    count: allCards.filter { $0.cardType?.lowercased() == "job" }.count,
                    label: "Jobs",
                    color: .blue
                )
                statItem(
                    count: allCards.filter { $0.cardType?.lowercased() == "skill" }.count,
                    label: "Skills",
                    color: .purple
                )
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func statItem(count: Int, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Onboarding Progress")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                let completed = planItems.filter { $0.status == .completed }.count
                Text("\(completed)/\(planItems.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            // Progress bar
            GeometryReader { geometry in
                let completed = planItems.filter { $0.status == .completed }.count
                let progress = planItems.isEmpty ? 0 : CGFloat(completed) / CGFloat(planItems.count)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var documentationGapsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("Documentation Gaps")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(documentationGaps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(Array(documentationGaps.enumerated()), id: \.offset) { _, gap in
                gapRow(gap)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func gapRow(_ gap: MergedCardInventory.DocumentationGap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(gap.cardTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 4) {
                gapTypeBadge(gap.gapType)
                Spacer()
            }

            if !gap.currentEvidence.isEmpty {
                Text(gap.currentEvidence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !gap.recommendedDocs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(gap.recommendedDocs.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func gapTypeBadge(_ gapType: MergedCardInventory.DocumentationGap.GapType) -> some View {
        let (text, color): (String, Color) = {
            switch gapType {
            case .missingPrimarySource:
                return ("Missing Source", .red)
            case .insufficientDetail:
                return ("Needs Detail", .orange)
            case .noQuantifiedOutcomes:
                return ("No Metrics", .yellow)
            }
        }()

        return Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
