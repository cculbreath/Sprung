import SwiftUI

/// Individual knowledge card display for the deck browser.
/// Shows card metadata, type badge, and content preview.
struct KnowledgeCardView: View {
    let card: KnowledgeCard
    let isTopCard: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onRegenerateSummary: (() -> Void)?

    @State private var isHovering = false
    @State private var isRegenerating = false

    private var cardTypeColor: Color {
        switch card.cardType {
        case .employment: return .blue
        case .project: return .green
        case .education: return .orange
        case .achievement: return .yellow
        case nil: return .gray
        }
    }

    private var cardTypeIcon: String {
        switch card.cardType {
        case .employment: return "briefcase.fill"
        case .project: return "folder.fill"
        case .education: return "graduationcap.fill"
        case .achievement: return "trophy.fill"
        case nil: return "doc.fill"
        }
    }

    private var wordCount: Int {
        card.narrative.split(separator: " ").count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with type badge
            headerSection

            Divider()
                .padding(.horizontal, 16)

            // Content preview
            contentSection

            Spacer(minLength: 0)

            // Footer with actions (only on top card)
            if isTopCard {
                Divider()
                    .padding(.horizontal, 16)
                footerSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardTypeColor.opacity(isTopCard ? 0.4 : 0.2), lineWidth: isTopCard ? 2 : 1)
        )
        .shadow(
            color: Color.black.opacity(isTopCard ? 0.15 : 0.08),
            radius: isTopCard ? 12 : 6,
            x: 0,
            y: isTopCard ? 4 : 2
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onChange(of: card.narrative) { _, _ in
            // Reset regenerating state when content updates
            isRegenerating = false
        }
    }

    private var cardBackground: some View {
        ZStack {
            // Base background
            Color(nsColor: .controlBackgroundColor)

            // Subtle gradient based on card type
            LinearGradient(
                colors: [
                    cardTypeColor.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Watermark icon (subtle)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: cardTypeIcon)
                        .font(.system(size: 80))
                        .foregroundStyle(cardTypeColor.opacity(0.04))
                        .padding(20)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge row
            HStack {
                Label(card.cardType?.displayName ?? "Card", systemImage: cardTypeIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cardTypeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(cardTypeColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                if card.isFromOnboarding {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Created during onboarding")
                }
            }

            // Title
            Text(card.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Metadata row
            HStack(spacing: 12) {
                if let org = card.organization, !org.isEmpty {
                    Label(org, systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let period = card.dateRange, !period.isEmpty {
                    Label(period, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let location = card.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Technologies/Skills section
                    if !card.technologies.isEmpty {
                        technologiesSection
                    }

                    // Facts section (grouped by category)
                    if !card.facts.isEmpty {
                        factsSection
                    }

                    // Suggested bullets section
                    if !card.suggestedBullets.isEmpty {
                        suggestedBulletsSection
                    }

                    // Content/Summary section - always show if present
                    if !card.narrative.isEmpty {
                        summarySection
                    }
                }
            }

            // Word count at bottom
            HStack {
                Spacer()
                Text("\(wordCount) words")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Summary", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let onRegenerateSummary = onRegenerateSummary, isTopCard {
                    Button(action: {
                        isRegenerating = true
                        onRegenerateSummary()
                    }) {
                        if isRegenerating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("Regenerate summary with AI")
                    .disabled(isRegenerating)
                }
            }

            Text(card.narrative)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var technologiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Skills & Technologies", systemImage: "cpu.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)

            FlowLayout(spacing: 4) {
                ForEach(card.technologies, id: \.self) { tech in
                    Text(tech)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Key Facts", systemImage: "lightbulb.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)

            ForEach(Array(card.factsByCategory.keys.sorted()), id: \.self) { category in
                if let facts = card.factsByCategory[category] {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.capitalized)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(facts) { fact in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(fact.statement)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var suggestedBulletsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Resume Bullets", systemImage: "list.bullet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

            ForEach(card.suggestedBullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 4) {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(bullet)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footerSection: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)

            Spacer()

            // Evidence anchors indicator
            if !card.evidenceAnchors.isEmpty {
                Label("\(card.evidenceAnchors.count) source\(card.evidenceAnchors.count == 1 ? "" : "s")", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Flow Layout for Tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}
