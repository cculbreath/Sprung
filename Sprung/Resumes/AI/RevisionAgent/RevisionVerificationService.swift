import Foundation
import SwiftOpenAI

// MARK: - Advisory Report

/// One grounding finding: a real (ground-truth) change whose content the
/// verification pass could not trace to the evidence corpus.
struct RevisionGroundingFlag: Identifiable {
    let id = UUID()
    /// Where the change landed, e.g. "work › [0] › highlights › [2]".
    let changeLocation: String
    /// The specific claims the verifier found unsupported.
    let unsupportedClaims: [String]
    /// A grounded rewording suggested by the verifier, when one exists.
    let suggestedRevision: String?
}

/// One coherence finding from the cross-section consistency pass.
struct RevisionCoherenceFlag: Identifiable {
    let id = UUID()
    /// e.g. "tense", "voice", "duplication", "summary-highlights".
    let category: String
    let detail: String
}

/// Advisory findings assembled at a completion boundary. NEVER blocking:
/// the user sees these on the completion card and decides.
struct RevisionAdvisoryReport {
    /// Ground-truth changes in the workspace that match no accepted proposal.
    var unreviewedWrites: [RevisionNodeDiff] = []
    /// Changes whose content could not be traced to the evidence corpus.
    var grounding: [RevisionGroundingFlag] = []
    /// Cross-section consistency findings over the final revised text.
    var coherence: [RevisionCoherenceFlag] = []
    /// Non-finding notes (e.g. a verification pass that could not run).
    /// Informational only — notes never gate a save.
    var notes: [String] = []

    var isEmpty: Bool {
        unreviewedWrites.isEmpty && grounding.isEmpty && coherence.isEmpty && notes.isEmpty
    }

    /// True when there is a finding the user should look at before accepting.
    /// Notes (verification unavailable) deliberately do NOT count — a failed
    /// check must never block a save.
    var hasActionableFlags: Bool {
        !unreviewedWrites.isEmpty || !grounding.isEmpty || !coherence.isEmpty
    }

    /// Render the findings for the model when the user declines a save after
    /// reviewing them, so the agent can address each one.
    var modelReadableSummary: String {
        var lines: [String] = []
        if !unreviewedWrites.isEmpty {
            lines.append("Changes written to the workspace that were never shown in an accepted proposal:")
            for entry in unreviewedWrites {
                let value = entry.newValue ?? entry.oldValue ?? ""
                lines.append("- [\(entry.kind.rawValue)] \(entry.nodePath): \(String(value.prefix(160)))")
            }
        }
        if !grounding.isEmpty {
            lines.append("Changes with unsupported claims (per the grounding audit):")
            for flag in grounding {
                lines.append("- \(flag.changeLocation): \(flag.unsupportedClaims.joined(separator: " | "))")
                if let suggestion = flag.suggestedRevision, !suggestion.isEmpty {
                    lines.append("  Suggested grounded revision: \(suggestion)")
                }
            }
        }
        if !coherence.isEmpty {
            lines.append("Coherence findings across the revised resume:")
            for flag in coherence {
                lines.append("- [\(flag.category)] \(flag.detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Verification Service

/// Runs the completion-boundary verification passes as CONTINUATIONS of the
/// live session conversation: same model, same tools, same system blocks, and
/// the same `tool_choice` as every session turn, so the session's cached
/// prefix is read instead of re-billed. (Forcing a tool or adding one would
/// invalidate the messages-tier cache covering the whole conversation — the
/// structured verdict is obtained by instructing a JSON-only text reply and
/// parsing it leniently.)
///
/// Every failure path returns nil: verification is a quality gate, never a
/// point of failure. The caller logs, notes the gap, and proceeds.
@MainActor
final class RevisionVerificationService {

    private weak var llmFacade: LLMFacade?
    private let modelId: String
    /// Verdicts are small; the budget only needs to cover the JSON reply.
    private let maxOutputTokens = 8192
    /// Inactivity threshold for the per-pass stream watchdog (mirrors the
    /// main loop's pattern): it fires only when NO events arrive for this
    /// long, so a healthy long reply — 80 verdicts with suggested revisions —
    /// keeps streaming and is never cut off, while a genuinely hung stream
    /// cannot hold the completion card hostage.
    private let streamStallTimeoutSeconds: TimeInterval = 180

    /// Timestamp of the most recent event on the active pass's stream.
    private var lastStreamEventDate = Date()

    /// The in-flight pass's stream task, so `cancel()` can interrupt it.
    private var activeStreamTask: Task<String, Error>?

    /// Latched by `cancel()`: the in-flight pass is torn down and any later
    /// pass fails fast (returns nil → the caller notes the gap and proceeds).
    private var isCancelled = false

    /// Per-call usage callback (input, cacheRead, cacheCreation, output) so
    /// the session's cumulative token telemetry stays honest.
    typealias UsageCallback = (Int, Int, Int, Int) -> Void

    init(llmFacade: LLMFacade, modelId: String) {
        self.llmFacade = llmFacade
        self.modelId = modelId
    }

    /// Interrupt verification: cancels the in-flight pass and makes any later
    /// pass fail fast. Wired to the agent's Cancel/ESC paths — verification
    /// must never hold a cancelled session hostage.
    func cancel() {
        isCancelled = true
        activeStreamTask?.cancel()
    }

    // MARK: - Grounding Pass (GR-1)

    /// Audit the ground-truth diff against the evidence corpus. Returns the
    /// flags for unsupported changes ([] when everything is supported), or
    /// nil when the pass could not run (API/decode failure — log and proceed).
    func verifyGrounding(
        baseMessages: [AnthropicMessage],
        pendingToolResults: [AnthropicContentBlock],
        system: AnthropicSystemContent,
        tools: [AnthropicTool],
        diff: RevisionWorkspaceDiff,
        corpus: String,
        askUserExchanges: [(question: String, answer: String)],
        onUsage: @escaping UsageCallback
    ) async -> [RevisionGroundingFlag]? {
        let entries = Array(diff.entries.prefix(Self.maxAuditedChanges))
        guard !entries.isEmpty else { return [] }

        let prompt = Self.groundingPrompt(
            entries: entries,
            corpus: corpus,
            askUserExchanges: askUserExchanges
        )

        guard let text = await runContinuation(
            baseMessages: baseMessages,
            pendingToolResults: pendingToolResults,
            system: system,
            tools: tools,
            promptText: prompt,
            passName: "grounding",
            onUsage: onUsage
        ) else { return nil }

        guard let data = Self.extractJSONObject(from: text) else {
            Logger.warning("RevisionVerification: grounding reply contained no JSON object", category: .ai)
            return nil
        }
        let response: GroundingResponse
        do {
            response = try JSONDecoder().decode(GroundingResponse.self, from: data)
        } catch {
            Logger.warning("RevisionVerification: could not decode grounding verdicts: \(error.localizedDescription)", category: .ai)
            return nil
        }

        var flags: [RevisionGroundingFlag] = []
        for verdict in response.verdicts {
            guard !verdict.supported || !(verdict.unsupportedClaims.isEmpty) else { continue }
            let location: String
            if entries.indices.contains(verdict.changeIndex) {
                location = entries[verdict.changeIndex].nodePath
            } else {
                location = "change \(verdict.changeIndex)"
            }
            flags.append(RevisionGroundingFlag(
                changeLocation: location,
                unsupportedClaims: verdict.unsupportedClaims,
                suggestedRevision: verdict.suggestedRevision
            ))
        }
        Logger.info(
            "RevisionVerification: grounding audited \(entries.count) change(s) → \(flags.count) flagged",
            category: .ai
        )
        return flags
    }

    // MARK: - Coherence Pass (RX-6)

    /// Check the final revised resume text for cross-section consistency.
    /// Returns the findings ([] when clean), or nil when the pass could not
    /// run.
    func verifyCoherence(
        baseMessages: [AnthropicMessage],
        pendingToolResults: [AnthropicContentBlock],
        system: AnthropicSystemContent,
        tools: [AnthropicTool],
        resumeText: String,
        onUsage: @escaping UsageCallback
    ) async -> [RevisionCoherenceFlag]? {
        guard let text = await runContinuation(
            baseMessages: baseMessages,
            pendingToolResults: pendingToolResults,
            system: system,
            tools: tools,
            promptText: Self.coherencePrompt(resumeText: resumeText),
            passName: "coherence",
            onUsage: onUsage
        ) else { return nil }

        guard let data = Self.extractJSONObject(from: text) else {
            Logger.warning("RevisionVerification: coherence reply contained no JSON object", category: .ai)
            return nil
        }
        let response: CoherenceResponse
        do {
            response = try JSONDecoder().decode(CoherenceResponse.self, from: data)
        } catch {
            Logger.warning("RevisionVerification: could not decode coherence findings: \(error.localizedDescription)", category: .ai)
            return nil
        }

        let flags = response.issues.map {
            RevisionCoherenceFlag(category: $0.category, detail: $0.description)
        }
        Logger.info("RevisionVerification: coherence pass → \(flags.count) finding(s)", category: .ai)
        return flags
    }

    // MARK: - Continuation Execution

    /// Issue one continuation request against the cached session prefix and
    /// return the model's text reply. nil on any failure (transport error,
    /// timeout, tool call instead of text).
    private func runContinuation(
        baseMessages: [AnthropicMessage],
        pendingToolResults: [AnthropicContentBlock],
        system: AnthropicSystemContent,
        tools: [AnthropicTool],
        promptText: String,
        passName: String,
        onUsage: @escaping UsageCallback
    ) async -> String? {
        guard !isCancelled else {
            Logger.info("RevisionVerification: \(passName) pass skipped — verification was cancelled", category: .ai)
            return nil
        }
        guard llmFacade != nil else {
            Logger.warning("RevisionVerification: LLM facade unavailable for \(passName) pass", category: .ai)
            return nil
        }

        // The ephemeral user message settles any tool_use ids still awaiting
        // results (Anthropic requires them answered in the next user message)
        // and then carries the verification instructions. It is never
        // persisted to the session history.
        let userBlocks = pendingToolResults + [.text(AnthropicTextBlock(text: promptText))]
        var messages = baseMessages
        messages.append(AnthropicMessage(role: "user", content: .blocks(userBlocks)))

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: system,
            maxTokens: maxOutputTokens,
            stream: true,
            tools: tools,
            toolChoice: .auto
        )

        lastStreamEventDate = Date()
        let streamTask = Task { @MainActor [weak self] () -> String in
            guard let self, let facade = self.llmFacade else { return "" }
            let stream = try await facade.anthropicMessagesStream(parameters: parameters)
            var processor = RevisionStreamProcessor()
            var collected = ""
            var sawToolCall = false

            for try await event in stream {
                try Task.checkCancellation()
                // Any raw event counts as activity for the stall watchdog.
                self.lastStreamEventDate = Date()
                for domainEvent in processor.process(event) {
                    switch domainEvent {
                    case .textFinalized(let text):
                        collected += text
                    case .toolCallReady(_, let name, _):
                        sawToolCall = true
                        Logger.warning("RevisionVerification: \(passName) pass called tool '\(name)' instead of replying — discarding", category: .ai)
                    case .usage(let input, let cacheRead, let cacheCreation, let output):
                        Logger.info(
                            "🤖 RevisionAgent \(passName)-verification usage (\(self.modelId)): input=\(input) cache_read=\(cacheRead) cache_create=\(cacheCreation) output=\(output)",
                            category: .ai
                        )
                        onUsage(input, cacheRead, cacheCreation, output)
                    case .streamError(let message):
                        Logger.warning("RevisionVerification: \(passName) stream error: \(message)", category: .ai)
                    case .textDelta, .stopReason:
                        break
                    }
                }
            }
            return sawToolCall ? "" : collected
        }

        activeStreamTask = streamTask

        // Inactivity watchdog (mirrors the main loop's): cancels the stream
        // only when NO events have arrived for `streamStallTimeoutSeconds`.
        // Not a total-duration cap — a long healthy reply is never cut off.
        let watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { return }
                guard let self else { return }
                if Date().timeIntervalSince(self.lastStreamEventDate) >= self.streamStallTimeoutSeconds {
                    Logger.warning(
                        "RevisionVerification: \(passName) stream stalled — no events for \(Int(self.streamStallTimeoutSeconds))s, cancelling",
                        category: .ai
                    )
                    streamTask.cancel()
                    return
                }
            }
        }
        defer {
            watchdog.cancel()
            activeStreamTask = nil
        }

        do {
            // streamTask is unstructured, so cancellation of the caller's
            // task (window teardown) does not propagate to it — forward it
            // explicitly so a closed window never waits out the watchdog.
            let text = try await withTaskCancellationHandler {
                try await streamTask.value
            } onCancel: {
                streamTask.cancel()
            }
            return text.isEmpty ? nil : text
        } catch {
            Logger.warning("RevisionVerification: \(passName) pass failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Prompts

    /// Cap on audited changes so a runaway diff cannot blow up the request.
    /// When the diff exceeds this, the caller surfaces a partial-audit note.
    static let maxAuditedChanges = 80

    private static func groundingPrompt(
        entries: [RevisionNodeDiff],
        corpus: String,
        askUserExchanges: [(question: String, answer: String)]
    ) -> String {
        var sections: [String] = []

        sections.append("""
        <coordinator>
        Stop revising. You are now acting as an ADVERSARIAL FACT-CHECKER auditing the \
        revision session above. Below is the GROUND-TRUTH list of changes actually written \
        to the resume workspace this session (computed by diffing the files on disk — not \
        from your own account of the session). Audit every change: assume the revision may \
        have fabricated or inflated claims.

        Valid evidence sources, in order of authority:
        1. The evidence corpus reproduced below (knowledge cards and skill bank).
        2. The original resume content (the PDF attached at the start of this conversation).
        3. The user's answers given during this session (reproduced below, if any).

        For EACH change, list every specific factual assertion in the NEW text (numbers, \
        dates, names, titles, technologies, outcomes, scope/scale claims) that NO evidence \
        source supports. Faithful paraphrase and reasonable summarization are fine; \
        invention, inflation, and details imported from nowhere are not. Pure deletions and \
        reorderings need no evidence. When a change has unsupported claims, also provide a \
        suggested revision: the same text with the unsupported claims removed or softened to \
        exactly what the evidence supports, changing nothing else.

        Be strict — an unverifiable claim on a resume can cost the applicant the job. But do \
        not punish grounded paraphrase, and do not flag stylistic rewording of existing \
        resume content.
        </coordinator>
        """)

        var changeLines: [String] = ["## Changes Under Audit (ground truth)"]
        for (index, entry) in entries.enumerated() {
            changeLines.append("")
            changeLines.append("### Change \(index) — \(entry.kind.rawValue) at \(entry.nodePath)")
            if let old = entry.oldValue, !old.isEmpty {
                changeLines.append("OLD: \(old)")
            }
            if let new = entry.newValue, !new.isEmpty {
                changeLines.append("NEW: \(new)")
            }
        }
        sections.append(changeLines.joined(separator: "\n"))

        if !askUserExchanges.isEmpty {
            var qaLines: [String] = ["## User Answers From This Session"]
            for exchange in askUserExchanges {
                qaLines.append("Q: \(exchange.question)")
                qaLines.append("A: \(exchange.answer)")
            }
            sections.append(qaLines.joined(separator: "\n"))
        }

        sections.append("""
        ## Evidence Corpus

        \(corpus.isEmpty ? "(no exported corpus — rely on the resume PDF and session answers)" : corpus)
        """)

        sections.append("""
        ## Response Format

        Do NOT call any tools. Reply with ONLY a JSON object — no prose, no code fences — \
        in exactly this shape, with one verdict per change in order, echoing each change's \
        index:

        {"verdicts": [{"changeIndex": 0, "supported": true, "unsupportedClaims": [], "suggestedRevision": null}]}

        Set "supported" to false and fill "unsupportedClaims" with the specific unsupported \
        assertions when a change fails the audit; include "suggestedRevision" (a grounded \
        rewording) whenever "supported" is false. Return a verdict for ALL \(entries.count) changes.
        """)

        return sections.joined(separator: "\n\n")
    }

    private static func coherencePrompt(resumeText: String) -> String {
        """
        <coordinator>
        Stop revising. You are now acting as a CONSISTENCY REVIEWER for the final revised \
        resume. The revised editable content is reproduced below; the PDF attached at the \
        start of this conversation shows the full document for surrounding context. Check \
        ONLY cross-section consistency — this is an advisory pass, not a rewrite:

        - tense: inconsistent verb tense within or across entries (e.g. past vs present for \
        the same role type)
        - voice: register or person shifts that make sections sound like different authors
        - duplication: the same claim, accomplishment, or skill stated in more than one place
        - summaryHighlights: the summary/objective promising things the highlights and \
        experience content do not reflect, or vice versa

        Report genuine findings only — do not invent issues to fill the list, and do not \
        flag deliberate stylistic variety.
        </coordinator>

        ## Revised Resume Content

        \(resumeText)

        ## Response Format

        Do NOT call any tools. Reply with ONLY a JSON object — no prose, no code fences — \
        in exactly this shape ("issues" empty when the resume is consistent):

        {"issues": [{"category": "tense", "description": "..."}]}

        Use one of these category values: "tense", "voice", "duplication", "summaryHighlights".
        """
    }

    // MARK: - Response Decoding

    private struct GroundingVerdict: Decodable {
        let changeIndex: Int
        let supported: Bool
        let unsupportedClaims: [String]
        let suggestedRevision: String?
    }

    private struct GroundingResponse: Decodable {
        let verdicts: [GroundingVerdict]
    }

    private struct CoherenceIssue: Decodable {
        let category: String
        let description: String
    }

    private struct CoherenceResponse: Decodable {
        let issues: [CoherenceIssue]
    }

    /// Extract the outermost JSON object from a text reply, tolerating prose
    /// or code fences around it.
    private static func extractJSONObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(text[start...end]).data(using: .utf8)
    }
}
