import AppKit
import SwiftUI

// MARK: - Resolved Card (view-side transcript retention)

/// A proposal/question/completion card that the user has resolved, retained in
/// the transcript with its outcome. This is view-side state only — the agent
/// keeps no record of dismissed cards.
struct ResolvedRevisionCard: Identifiable {
    enum Kind {
        case proposal(ChangeProposal, response: ProposalResponse)
        case question(String, answer: String)
        case completion(summary: String, accepted: Bool, report: RevisionAdvisoryReport?)
    }

    let id = UUID()
    /// Index into the agent's message list this card precedes. Captured as
    /// `messages.count` at resolution time — the agent appends the user's
    /// response message immediately after, so the card renders just before it.
    let anchorIndex: Int
    let kind: Kind
}

/// Chat-like message stream for the revision agent session.
struct RevisionChatView: View {
    let messages: [RevisionMessage]
    let currentProposal: ChangeProposal?
    let currentQuestion: String?
    let currentCompletionSummary: String?
    /// Advisory findings accompanying the active completion card (ground-truth
    /// unreviewed writes, grounding flags, coherence flags).
    let currentAdvisoryReport: RevisionAdvisoryReport?
    let isRunning: Bool
    let sessionEnded: Bool
    let onProposalResponse: (ProposalResponse) -> Void
    let onQuestionResponse: (String) -> Void
    let onCompletionResponse: (Bool) -> Void
    let onUserMessage: (String) -> Void
    let onInterruptWithMessage: (String) -> Void
    let onCancelStream: () -> Void

    @State private var questionAnswer: String = ""
    @State private var chatInput: String = ""
    @State private var shouldAutoScroll = true
    @State private var resolvedCards: [ResolvedRevisionCard] = []

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Index-based identity keeps the streaming assistant row
                        // stable while its content grows (the agent replaces the
                        // last message value on every delta).
                        ForEach(messages.indices, id: \.self) { index in
                            anchoredResolvedCards(at: index)
                            messageRow(messages[index])
                        }
                        trailingResolvedCards()

                        // Active proposal card
                        if let proposal = currentProposal {
                            RevisionProposalView(
                                proposal: proposal,
                                onRespond: { response in
                                    resolvedCards.append(ResolvedRevisionCard(
                                        anchorIndex: messages.count,
                                        kind: .proposal(proposal, response: response)
                                    ))
                                    onProposalResponse(response)
                                }
                            )
                            .id("proposal")
                        }

                        // Active question
                        if let question = currentQuestion {
                            questionCard(question)
                                .id("question")
                        }

                        // Completion card
                        if let summary = currentCompletionSummary {
                            completionCard(summary)
                                .id("completion")
                        }

                        // Streaming indicator
                        if isRunning && currentProposal == nil && currentQuestion == nil && currentCompletionSummary == nil {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .id("streaming")
                        }

                        // Bottom anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) {
                    if shouldAutoScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                // Follow content growth while the last message streams in.
                .onChange(of: messages.last?.content) {
                    if shouldAutoScroll {
                        scrollProxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: currentProposal != nil) {
                    if shouldAutoScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("proposal", anchor: .top)
                        }
                    }
                }
                .onChange(of: currentQuestion) {
                    if shouldAutoScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("question", anchor: .top)
                        }
                    }
                }
                .onChange(of: currentCompletionSummary) {
                    if shouldAutoScroll, currentCompletionSummary != nil {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("completion", anchor: .top)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            chatInputBar
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Chat Input Bar

    @ViewBuilder
    private var chatInputBar: some View {
        if sessionEnded {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text("Session ended — close this window and start a new Customize session to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.bar)
        } else {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Send a message...", text: $chatInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    )
                    .onSubmit { submitMessage(interrupt: false) }
                    .onKeyPress(.return, phases: .down) { press in
                        // ⌥⏎ interrupts the agent immediately with the message.
                        guard press.modifiers.contains(.option) else { return .ignored }
                        submitMessage(interrupt: true)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if isRunning {
                            onCancelStream()
                            return .handled
                        }
                        return .ignored
                    }

                // Send button — click queues, ⌥-click interrupts now
                Button {
                    submitMessage(interrupt: NSEvent.modifierFlags.contains(.option))
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send at the next turn boundary (⏎). ⌥-click or ⌥⏎ interrupts the agent now.")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func submitMessage(interrupt: Bool) {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatInput = ""
        recordPendingCardResolution(answeredBy: text)
        if interrupt {
            onInterruptWithMessage(text)
        } else {
            onUserMessage(text)
        }
    }

    /// A chat message sent while a card is pending resolves that card inside
    /// the agent (completion → continue editing, proposal → feedback,
    /// question → answer). Mirror the agent's resolution priority so the
    /// transcript retains the card with the outcome the agent applied.
    private func recordPendingCardResolution(answeredBy text: String) {
        if let summary = currentCompletionSummary {
            resolvedCards.append(ResolvedRevisionCard(
                anchorIndex: messages.count,
                kind: .completion(summary: summary, accepted: false, report: currentAdvisoryReport)
            ))
        } else if let proposal = currentProposal {
            resolvedCards.append(ResolvedRevisionCard(
                anchorIndex: messages.count,
                kind: .proposal(proposal, response: .modified(feedback: text))
            ))
        } else if let question = currentQuestion {
            resolvedCards.append(ResolvedRevisionCard(
                anchorIndex: messages.count,
                kind: .question(question, answer: text)
            ))
        }
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(_ message: RevisionMessage) -> some View {
        switch message.role {
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 4)

                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

        case .user:
            HStack(alignment: .top, spacing: 10) {
                Spacer(minLength: 60)

                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }

        case .toolActivity:
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 30)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Question Card

    @ViewBuilder
    private func questionCard(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(question)
                    .font(.body)
            }

            TextEditor(text: $questionAnswer)
                .font(.body)
                .frame(minHeight: 40, maxHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.quaternary)
                        )
                )

            HStack {
                Spacer()
                Button("Submit") {
                    let answer = questionAnswer
                    questionAnswer = ""
                    resolvedCards.append(ResolvedRevisionCard(
                        anchorIndex: messages.count,
                        kind: .question(question, answer: answer)
                    ))
                    onQuestionResponse(answer)
                }
                .buttonStyle(.borderedProminent)
                .disabled(questionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Completion Card

    /// Presentation tone for a completion card. The agent reuses the
    /// completion-card machinery for its keep-changes-so-far offers and
    /// publishes only the summary string, so tone is inferred from the fixed
    /// agent-authored openings of those offers
    /// (`ResumeRevisionAgent.handleExitCleanup` / `finishAfterStalledSession`).
    /// The agent's status is still `.running` while the card is presented, so
    /// status cannot distinguish the cases. Unrecognized summaries — the
    /// model's own `complete_revision` text — render as success; if the agent
    /// wording drifts this degrades to the success presentation, never the
    /// reverse.
    private enum CompletionTone {
        /// Genuine completion via `complete_revision`.
        case success
        /// Error exit with applied work — Accept keeps it, declining discards
        /// it and ends the session.
        case errorExit
        /// Stalled session with applied work — Accept keeps it, declining
        /// continues the session.
        case stalled
        /// Save gated on verification advisories — Accept saves anyway,
        /// declining continues the session.
        case saveGate
    }

    private func completionTone(for summary: String) -> CompletionTone {
        if summary.hasPrefix("The revision session ended early") { return .errorExit }
        if summary.hasPrefix("The assistant stopped taking actions") { return .stalled }
        if summary.hasPrefix("Save requested") { return .saveGate }
        return .success
    }

    private func completionHeadline(for tone: CompletionTone) -> String {
        switch tone {
        case .success: return "Revision Complete"
        case .errorExit: return "Session Ended Early — Keep Applied Changes?"
        case .stalled: return "Session Stalled — Keep Changes So Far?"
        case .saveGate: return "Save with Advisories?"
        }
    }

    @ViewBuilder
    private func completionCard(_ summary: String) -> some View {
        let tone = completionTone(for: summary)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tone == .success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(tone == .success ? Color.green : Color.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(completionHeadline(for: tone))
                        .font(.headline)
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            if let report = currentAdvisoryReport, !report.isEmpty {
                advisorySection(report)
            }

            HStack(spacing: 10) {
                Spacer()
                // Button labels stay fixed across tones: the agent-authored
                // offer summaries name these buttons verbatim ("Accept to keep
                // them…", "Choosing \"Continue Editing\"…").
                Button("Continue Editing") {
                    resolvedCards.append(ResolvedRevisionCard(
                        anchorIndex: messages.count,
                        kind: .completion(summary: summary, accepted: false, report: currentAdvisoryReport)
                    ))
                    onCompletionResponse(false)
                }
                .buttonStyle(.bordered)

                Button("Accept") {
                    resolvedCards.append(ResolvedRevisionCard(
                        anchorIndex: messages.count,
                        kind: .completion(summary: summary, accepted: true, report: currentAdvisoryReport)
                    ))
                    onCompletionResponse(true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Advisory Section

    /// Advisory findings rendered inside the completion card. These never
    /// block — the user reads them and decides with the card's buttons.
    @ViewBuilder
    private func advisorySection(_ report: RevisionAdvisoryReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !report.unreviewedWrites.isEmpty {
                advisoryGroupHeader(
                    icon: "eye.slash",
                    title: "Applied without review (\(report.unreviewedWrites.count))",
                    subtitle: "These changes are in the working copy but were never part of an accepted proposal."
                )
                ForEach(report.unreviewedWrites) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.kind.rawValue.capitalized) — \(entry.nodePath)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let value = entry.newValue ?? entry.oldValue, !value.isEmpty {
                            Text(value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, 18)
                }
            }

            if !report.grounding.isEmpty {
                advisoryGroupHeader(
                    icon: "checkmark.shield",
                    title: "Unsupported claims (\(report.grounding.count))",
                    subtitle: "The grounding audit could not trace these to your knowledge cards, skill bank, resume, or answers."
                )
                ForEach(report.grounding) { flag in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flag.changeLocation)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        ForEach(flag.unsupportedClaims, id: \.self) { claim in
                            Text("• \(claim)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let suggestion = flag.suggestedRevision, !suggestion.isEmpty {
                            Text("Suggested: \(suggestion)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, 18)
                }
            }

            if !report.coherence.isEmpty {
                advisoryGroupHeader(
                    icon: "text.alignleft",
                    title: "Coherence (\(report.coherence.count))",
                    subtitle: "Cross-section consistency findings in the revised resume."
                )
                ForEach(report.coherence) { flag in
                    Text("• [\(flag.category)] \(flag.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 18)
                }
            }

            ForEach(report.notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.2))
                )
        )
    }

    @ViewBuilder
    private func advisoryGroupHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Resolved Cards (transcript retention)

    /// Resolved cards anchored immediately before the message at `index`.
    @ViewBuilder
    private func anchoredResolvedCards(at index: Int) -> some View {
        ForEach(resolvedCards.filter { $0.anchorIndex == index }) { card in
            resolvedCardView(card)
        }
    }

    /// Resolved cards whose anchor sits at or past the end of the message list
    /// (no response message has been appended after them yet).
    @ViewBuilder
    private func trailingResolvedCards() -> some View {
        ForEach(resolvedCards.filter { $0.anchorIndex >= messages.count }) { card in
            resolvedCardView(card)
        }
    }

    @ViewBuilder
    private func resolvedCardView(_ card: ResolvedRevisionCard) -> some View {
        switch card.kind {
        case .proposal(let proposal, let response):
            resolvedProposalCard(proposal, response: response)
        case .question(let question, _):
            resolvedQuestionCard(question)
        case .completion(let summary, let accepted, let report):
            resolvedCompletionCard(summary, accepted: accepted, report: report)
        }
    }

    @ViewBuilder
    private func resolvedProposalCard(_ proposal: ChangeProposal, response: ProposalResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(proposal.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                outcomeBadge(proposalOutcomeLabel(response), color: proposalOutcomeColor(response))
            }

            ForEach(Array(proposal.changes.enumerated()), id: \.offset) { index, change in
                HStack(alignment: .top, spacing: 6) {
                    Text(change.section)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(change.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    if let label = itemizedDecisionLabel(response, index: index) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resolvedCardBackground)
    }

    @ViewBuilder
    private func resolvedQuestionCard(_ question: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
            Text(question)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            outcomeBadge("Answered", color: .blue)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resolvedCardBackground)
    }

    @ViewBuilder
    private func resolvedCompletionCard(_ summary: String, accepted: Bool, report: RevisionAdvisoryReport?) -> some View {
        let tone = completionTone(for: summary)
        let badge = resolvedCompletionBadge(tone: tone, accepted: accepted)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                resolvedCompletionIcon(tone: tone, accepted: accepted)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                outcomeBadge(badge.label, color: badge.color)
            }
            if let report, report.hasActionableFlags {
                Text(resolvedAdvisorySummary(report))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resolvedCardBackground)
    }

    private func resolvedAdvisorySummary(_ report: RevisionAdvisoryReport) -> String {
        var parts: [String] = []
        if !report.unreviewedWrites.isEmpty { parts.append("\(report.unreviewedWrites.count) unreviewed write(s)") }
        if !report.grounding.isEmpty { parts.append("\(report.grounding.count) grounding flag(s)") }
        if !report.coherence.isEmpty { parts.append("\(report.coherence.count) coherence flag(s)") }
        return "Advisories at resolution: " + parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func resolvedCompletionIcon(tone: CompletionTone, accepted: Bool) -> some View {
        switch tone {
        case .success:
            Image(systemName: accepted ? "checkmark.seal.fill" : "checkmark.seal")
                .foregroundStyle(accepted ? Color.green : Color.secondary)
        case .errorExit, .stalled, .saveGate:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.orange)
        }
    }

    private func resolvedCompletionBadge(tone: CompletionTone, accepted: Bool) -> (label: String, color: Color) {
        switch (tone, accepted) {
        case (.success, true):
            return ("Accepted", .green)
        case (.errorExit, true), (.stalled, true):
            return ("Kept changes", .green)
        case (.saveGate, true):
            return ("Saved with advisories", .green)
        case (.errorExit, false):
            return ("Discarded", .red)
        case (.success, false), (.stalled, false), (.saveGate, false):
            return ("Continued editing", .orange)
        }
    }

    private func outcomeBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
            .fixedSize()
    }

    private var resolvedCardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }

    private func proposalOutcomeLabel(_ response: ProposalResponse) -> String {
        switch response {
        case .accepted:
            return "Accepted"
        case .rejected:
            return "Rejected"
        case .modified:
            return "Feedback sent"
        case .itemized(let items):
            var parts: [String] = []
            let accepted = items.filter { $0.kind == .accept }.count
            let edited = items.filter { $0.kind == .edit }.count
            let rejected = items.filter { $0.kind == .reject }.count
            let feedback = items.filter { $0.kind == .feedback }.count
            if accepted > 0 { parts.append("\(accepted) accepted") }
            if edited > 0 { parts.append("\(edited) edited") }
            if rejected > 0 { parts.append("\(rejected) rejected") }
            if feedback > 0 { parts.append("\(feedback) feedback") }
            return parts.isEmpty ? "Reviewed" : parts.joined(separator: ", ")
        }
    }

    private func proposalOutcomeColor(_ response: ProposalResponse) -> Color {
        switch response {
        case .accepted: return .green
        case .rejected: return .red
        case .modified: return .blue
        case .itemized: return .orange
        }
    }

    private func itemizedDecisionLabel(_ response: ProposalResponse, index: Int) -> String? {
        guard case .itemized(let items) = response,
              let item = items.first(where: { $0.index == index }) else { return nil }
        switch item.kind {
        case .accept: return "accepted"
        case .reject: return "rejected"
        case .feedback: return "feedback"
        case .edit: return "edited"
        }
    }
}
