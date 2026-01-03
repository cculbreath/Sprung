import SwiftUI

/// Tab content showing knowledge cards summary and browser access.
struct KnowledgeTabContent: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var showBrowser = false

    private var allCards: [ResRef] {
        coordinator.allKnowledgeCards
    }

    private var resRefStore: ResRefStore {
        coordinator.getResRefStore()
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
                    Task { await coordinator.syncResRefToFilesystem(card) }
                },
                onCardDeleted: { card in
                    resRefStore.deleteResRef(card)
                },
                onCardAdded: { card in
                    resRefStore.addResRef(card)
                    Task { await coordinator.syncResRefToFilesystem(card) }
                },
                llmFacade: coordinator.llmFacade
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
                    count: allCards.filter { $0.cardType?.lowercased() == "employment" }.count,
                    label: "Employment",
                    color: .blue
                )
                statItem(
                    count: allCards.filter { $0.cardType?.lowercased() == "project" }.count,
                    label: "Projects",
                    color: .green
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
}
