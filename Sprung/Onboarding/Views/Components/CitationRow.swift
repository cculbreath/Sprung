import SwiftUI
struct CitationRow: View {
    let claim: String
    let evidence: EvidenceItem
    let isExpanded: Bool
    let isRejected: Bool
    let onToggleExpand: () -> Void
    let onToggleReject: () -> Void
    init(
        claim: String,
        evidence: EvidenceItem,
        isExpanded: Bool = false,
        isRejected: Bool = false,
        onToggleExpand: @escaping () -> Void,
        onToggleReject: @escaping () -> Void
    ) {
        self.claim = claim
        self.evidence = evidence
        self.isExpanded = isExpanded
        self.isRejected = isRejected
        self.onToggleExpand = onToggleExpand
        self.onToggleReject = onToggleReject
    }

    /// Parse markdown for rich text display, with fallback to plain text
    private var markdownText: AttributedString {
        if let attributed = try? AttributedString(
            markdown: claim,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(claim)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { !isRejected },
                    set: { _ in onToggleReject() }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                // Render markdown in claims (supports **bold**, bullet points, etc.)
                Text(markdownText)
                    .strikethrough(isRejected, pattern: .solid, color: .secondary)
                    .foregroundStyle(isRejected ? .secondary : .primary)
                Spacer()
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide citation" : "Show citation")
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\"\(evidence.quote)\"")
                        .italic()
                        .padding(.leading, 22)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(evidence.source)
                                .font(.caption)
                            if let locator = evidence.locator, !locator.isEmpty {
                                Text(locator)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 22)
                }
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 4)
    }
}
