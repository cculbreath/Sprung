//
//  ConversationLog.swift
//  Sprung
//
//  Single source of truth for conversation state. Append-only sequence
//  with gated user message appending. Tool call slots are filled as
//  results arrive; user messages are blocked until all slots are filled.
//
//  Key invariants:
//  - At most ONE entry (the last) can have nil tool result slots
//  - User messages cannot append until all slots are filled
//  - On interrupt, pending slots are filled with synthetic results
//
//  PROMPT-CACHE INVARIANT (wire-text capture):
//  History must replay byte-identically across requests or prompt caching breaks.
//  At request-build time, volatile content (<interview_context>, <coordinator>,
//  todo list) is merged into the latest user message. The exact merged text is
//  written back here at send time (separate from the display text, which would
//  otherwise pollute the UI transcript):
//  - userWireText[entryId]      — final merged text of a sent user message
//                                 (keyed by the id captured at append/enqueue time,
//                                 never by log position — appends race the build)
//  - userAttachments[entryId]   — chatbox attachment (image/PDF base64) sent with
//                                 a user message, replayed in the exact position
//                                 the original request used (text first, then
//                                 attachment)
//  - toolContextText[entryId]   — context text block appended after an assistant
//                                 entry's tool_results in the wire user message
//  - toolResultWireText[callId] — exact tool_result content string as FIRST
//                                 serialized to the wire (pending placeholder if
//                                 the tool hadn't finished); reused on every
//                                 rebuild — NEVER mutated. A result that lands
//                                 after its placeholder was serialized is queued
//                                 in pendingWireUpdates and delivered as a
//                                 <tool_result_update> block in the next request's
//                                 tail (in-place upgrades invalidated the cached
//                                 prefix on every later request — 26 busts in one
//                                 session, ~6.6M cache-write tokens)
//  - coordinatorWireTurns       — standalone coordinator user turns that have no
//                                 ConversationEntry at all (wire-only)
//  getWireSnapshot() interleaves these so AnthropicHistoryBuilder reproduces the
//  exact bytes previously sent. The side tables are in-memory only: after a
//  session restore the replay falls back to display text (the 5-minute cache
//  never survives an app restart, so nothing is lost).
//
//  ACCEPTANCE INVARIANT: building the same request twice with no new entries must
//  produce byte-identical messages JSON; building turn N+1 must reproduce turn N's
//  messages as an exact prefix (modulo cache_control placement, which the API
//  ignores for prefix matching).
//

import Foundation

// MARK: - ConversationLog Actor

/// Single source of truth for conversation state
actor ConversationLog {

    // MARK: - State

    private(set) var entries: [ConversationEntry] = []
    private let operations: OperationTracker
    private let eventBus: EventBus

    // MARK: - Wire-Text State (see PROMPT-CACHE INVARIANT in file header)

    /// Exact wire text sent for a user entry (keyed by entry id)
    private var userWireText: [UUID: String] = [:]
    /// Chatbox attachment (image/PDF) sent with a user entry (keyed by entry id)
    private var userAttachments: [UUID: WireAttachment] = [:]
    /// Context text block appended after an assistant entry's tool_results (keyed by entry id)
    private var toolContextText: [UUID: String] = [:]
    /// Exact tool_result content string as first serialized to the wire (keyed by callId)
    private var toolResultWireText: [String: String] = [:]
    /// Wire-only coordinator user turns, anchored after the entry that preceded them
    /// (nil anchor = before the first entry)
    private var coordinatorWireTurns: [(afterEntryId: UUID?, text: String)] = []

    /// Late tool results awaiting cache-stable delivery: the slot's wire bytes are
    /// frozen (placeholder or synthetic fill), so the real output is rendered as a
    /// <tool_result_update> block in the next request's volatile tail instead of
    /// being written back into history. Deduped by callId, drained at request build.
    private var pendingWireUpdates: [WireToolUpdate] = []

    /// Placeholder serialized for a tool_result whose tool hasn't finished when the
    /// request is built. Recorded into `toolResultWireText` so the same bytes replay
    /// forever; the real result is delivered via `pendingWireUpdates`.
    static let pendingToolResultPlaceholder = #"{"status":"pending","reason":"Tool execution in progress"}"#

    /// Serialized in place of an empty tool output (Anthropic rejects empty
    /// tool_result content). Substituted at recording time so `toolResultWireText`
    /// is the exact wire string in all cases.
    static let emptyToolResultSubstitute = #"{"status":"completed"}"#

    // MARK: - Initialization

    init(operations: OperationTracker, eventBus: EventBus) {
        self.operations = operations
        self.eventBus = eventBus
        Logger.info("ConversationLog initialized", category: .ai)
    }

    // MARK: - Queries

    /// Check if the last assistant entry has unresolved tool calls
    var hasPendingToolCalls: Bool {
        guard case .assistant(_, _, let toolCalls?, _) = entries.last else {
            return false
        }
        return toolCalls.contains { !$0.isResolved }
    }

    /// Get IDs of unresolved tool calls in last entry
    var pendingToolCallIds: [String] {
        guard case .assistant(_, _, let toolCalls?, _) = entries.last else {
            return []
        }
        return toolCalls.filter { !$0.isResolved }.map { $0.callId }
    }

    // MARK: - User Message (Gated)

    /// Append user message - fills pending tool slots first if needed
    /// This is the gating mechanism that ensures the log is always valid
    ///
    /// SEND-ORDER INVARIANT: user entries are created at request-BUILD time
    /// (AnthropicRequestBuilder), never at enqueue/click time. Builds are
    /// serialized behind any in-flight stream, so a user entry can never land
    /// before an assistant entry that finalizes after it — the log is strictly
    /// send-ordered and a rebuilt history can never end with an assistant turn.
    ///
    /// - Parameter id: The entry id reserved at enqueue time. Idempotent: if an
    ///   entry with this id already exists (a failed request being retried),
    ///   the append is a no-op so retries never duplicate the turn.
    /// - Returns: The entry's id. Callers that later send this entry MUST
    ///   carry this id to `setWireText(forUserEntryId:text:)` so the wire-text
    ///   capture can never land on a different entry (see PROMPT-CACHE INVARIANT).
    @discardableResult
    func appendUser(id: UUID = UUID(), text: String, isSystemGenerated: Bool) async -> UUID {
        // Idempotent on id: a retried request build re-uses its reserved entry
        if entries.contains(where: { $0.id == id }) {
            Logger.debug("ConversationLog: appendUser — entry \(id.uuidString.prefix(8)) already exists (retry), skipping append", category: .ai)
            return id
        }

        // If there are pending tool calls, resolve them first
        if hasPendingToolCalls {
            let pendingIds = pendingToolCallIds
            Logger.info("ConversationLog: Gating user message, filling \(pendingIds.count) pending slots", category: .ai)

            // Cancel any running operations
            for callId in pendingIds {
                await operations.cancel(callId: callId, reason: "User interrupted")
            }

            // Fill slots with results (real from completed ops, synthetic from cancelled)
            for callId in pendingIds {
                if let result = await operations.getResult(callId: callId) {
                    setToolResult(callId: callId, output: result, status: .cancelled)
                } else {
                    // No operation found, use generic cancelled result
                    setToolResult(callId: callId, output: #"{"status":"cancelled","reason":"User interrupted"}"#, status: .cancelled)
                }
            }
        }

        // Now safe to append user message
        let entry = ConversationEntry.user(
            id: id,
            text: text,
            isSystemGenerated: isSystemGenerated,
            timestamp: Date()
        )
        entries.append(entry)

        Logger.info("ConversationLog: Appended user message (total: \(entries.count))", category: .ai)

        // Publish event for persistence
        await eventBus.publish(.llm(.conversationEntryAppended(entry: entry)))
        return id
    }

    /// Remove a user entry whose request failed to send.
    /// The failed chatbox text is restored to the input box for manual resend;
    /// leaving the entry in the log would replay a turn the model never received
    /// and duplicate the message when the user resends it. Wire side tables for
    /// the entry are cleared so nothing replays its bytes.
    func removeUserEntry(id: UUID) async {
        guard let index = entries.lastIndex(where: { $0.id == id && $0.isUser }) else {
            Logger.debug("ConversationLog: removeUserEntry — no user entry \(id.uuidString.prefix(8))", category: .ai)
            return
        }
        entries.remove(at: index)
        userWireText.removeValue(forKey: id)
        userAttachments.removeValue(forKey: id)
        Logger.info("ConversationLog: Removed failed user entry \(id.uuidString.prefix(8)) (total: \(entries.count))", category: .ai)
    }

    // MARK: - Assistant Message

    /// Append assistant message with optional tool calls (slots start as nil)
    /// Auto-fills any orphaned tool slots from previous assistant entry to maintain
    /// Anthropic API invariant: every tool_use must have tool_result immediately after.
    func appendAssistant(id: UUID, text: String, toolCalls: [ToolCallInfo]?) async {
        // CRITICAL: If the previous entry is an assistant with pending tool calls,
        // fill them with synthetic results before appending new assistant message.
        // This maintains the invariant: only the LAST entry can have pending slots.
        // Anthropic API requires: every tool_use must have a tool_result immediately after.
        if hasPendingToolCalls {
            let pendingIds = pendingToolCallIds
            Logger.warning("ConversationLog: Auto-filling \(pendingIds.count) orphaned tool slot(s) before new assistant message", category: .ai)

            for callId in pendingIds {
                // Cancel the operation if it's still running
                await operations.cancel(callId: callId, reason: "LLM sent new message before tool response")

                // Fill with synthetic result - check if operation has a result
                let result = await operations.getResult(callId: callId) ?? #"{"status":"superseded","reason":"LLM sent new message before tool response"}"#
                setToolResult(callId: callId, output: result, status: .cancelled)
            }
        }

        let calls = toolCalls?.map { info in
            ToolCallSlot(
                callId: info.id,
                name: info.name,
                arguments: info.arguments,
                result: nil,
                status: .pending
            )
        }

        let entry = ConversationEntry.assistant(
            id: id,
            text: text,
            toolCalls: calls,
            timestamp: Date()
        )
        entries.append(entry)

        let toolCount = calls?.count ?? 0
        Logger.info("ConversationLog: Appended assistant message with \(toolCount) tool call(s)", category: .ai)

        // Publish event for persistence
        await eventBus.publish(.llm(.conversationEntryAppended(entry: entry)))
    }

    // MARK: - Tool Result (Slot Fill)

    /// Fill a tool result slot in the last assistant entry
    /// Returns true if slot was found and filled, false if slot not found (orphaned/already filled)
    ///
    /// PROMPT-CACHE INVARIANT: a result that arrives after its slot's wire bytes
    /// were serialized (pending placeholder) or after the slot was synthetically
    /// resolved (auto-fill/gating) is queued for tail delivery as a
    /// <tool_result_update> block — the recorded wire bytes are never mutated.
    @discardableResult
    func setToolResult(callId: String, output: String, status: ToolCallStatus = .completed) -> Bool {
        let wireOutput = output.isEmpty ? Self.emptyToolResultSubstitute : output

        guard case .assistant(let id, let text, var toolCalls?, let timestamp) = entries.last,
              let index = toolCalls.firstIndex(where: { $0.callId == callId }) else {
            // Slot is not in the last entry. If the call exists earlier in history
            // its wire bytes are frozen (placeholder or synthetic fill) and the
            // model has never seen this real output — deliver it at the tail.
            if let slot = findSlot(callId: callId) {
                if toolResultWireText[callId] != wireOutput {
                    enqueueWireUpdate(callId: callId, name: slot.name, output: wireOutput, status: status)
                    Logger.info("ConversationLog: Late result for \(callId.prefix(8)) (slot not in last entry) — queued tail delivery", category: .ai)
                }
            } else {
                Logger.warning("ConversationLog: Tool result for unknown call \(callId.prefix(8))", category: .ai)
            }
            return false
        }

        // Check if already resolved (prevent double-fill). The slot's recorded
        // result (typically a synthetic auto-fill) keeps its frozen wire bytes;
        // the real output still reaches the model via tail delivery.
        if toolCalls[index].isResolved {
            if toolResultWireText[callId] != wireOutput {
                enqueueWireUpdate(callId: callId, name: toolCalls[index].name, output: wireOutput, status: status)
                Logger.info("ConversationLog: Late result for \(callId.prefix(8)) (slot already resolved) — queued tail delivery", category: .ai)
            } else {
                Logger.warning("ConversationLog: Tool slot \(callId.prefix(8)) already resolved, skipping", category: .ai)
            }
            return false
        }

        // Fill the slot
        toolCalls[index].result = output
        toolCalls[index].status = status

        // If this slot was already serialized to the wire (as the pending
        // placeholder), those bytes stay frozen — queue the real result for
        // tail delivery instead of mutating history.
        if let recorded = toolResultWireText[callId], recorded != wireOutput {
            enqueueWireUpdate(callId: callId, name: toolCalls[index].name, output: wireOutput, status: status)
            Logger.info("ConversationLog: Result for \(callId.prefix(8)) arrived after placeholder serialization — queued tail delivery", category: .ai)
        }

        // Replace last entry with updated version
        entries[entries.count - 1] = .assistant(
            id: id,
            text: text,
            toolCalls: toolCalls,
            timestamp: timestamp
        )

        Logger.debug("ConversationLog: Filled tool slot \(callId.prefix(8)) (\(status))", category: .ai)

        // Publish event for persistence update
        Task {
            await eventBus.publish(.llm(.toolResultFilled(callId: callId, status: status.rawValue)))
        }
        return true
    }

    // MARK: - Wire-Text Capture (Prompt-Cache Byte Stability)

    /// A chatbox attachment (image or PDF) in exact wire form. The base64 string is
    /// stored verbatim so replays are byte-identical with the original send.
    /// In-memory only, like the other wire side tables (cleared on restore/reset).
    struct WireAttachment: Sendable, Equatable {
        let base64Data: String
        let mediaType: String
    }

    /// A tool call in exact wire form: `result` is the tool_result content string as
    /// first serialized to the wire (never optional — pending calls carry the
    /// recorded placeholder), so rebuilds replay identical bytes.
    struct WireToolCall: Sendable {
        let callId: String
        let name: String
        let arguments: String
        let result: String
    }

    /// A tool result that completed after its slot's wire bytes were frozen.
    /// Rendered as a <tool_result_update> block in the next request's volatile
    /// tail (where it freezes into history like all other wire text).
    struct WireToolUpdate: Sendable {
        let callId: String
        let name: String
        let output: String
        let status: ToolCallStatus
    }

    /// A conversation turn in exact wire form, for byte-identical history replay.
    enum WireEntry: Sendable {
        /// User turn — `text` is the exact wire text (merged context + message) when
        /// the turn has been sent, otherwise the display text. `attachment` is the
        /// chatbox image/PDF sent with the turn, replayed after the text block in
        /// the same order the original request used.
        case user(text: String, attachment: WireAttachment?)
        /// Assistant turn with its tool calls. `toolContextText` is the context text
        /// block appended after this turn's tool_results in the wire user message.
        case assistant(text: String, toolCalls: [WireToolCall]?, toolContextText: String?)
    }

    /// Record the final merged wire text for a pending user entry (called at send time).
    ///
    /// Keyed by entry id — NOT by log position. Appends happen outside the serialized
    /// send queue (chatbox appends immediately; system-generated messages append at
    /// enqueue time; the stream queue reorders chatbox/tool-response requests), so
    /// another entry can land between this entry's append and its request build.
    /// Keying by id guarantees the wire text can never be attributed to that other
    /// entry, which would permanently corrupt history replay.
    func setWireText(forUserEntryId id: UUID, text: String) -> Bool {
        guard let entry = entries.last(where: { $0.id == id }), entry.isUser else {
            Logger.warning("ConversationLog: setWireText — no user entry with id \(id.uuidString.prefix(8))", category: .ai)
            return false
        }
        userWireText[id] = text
        return true
    }

    /// Record the chatbox attachment (image or PDF) sent with a user entry, called at
    /// request-build time alongside `setWireText(forUserEntryId:text:)`. Without this
    /// record the attachment blocks would be silently dropped from every later
    /// history rebuild — a permanent prefix divergence from that turn onward.
    func setAttachment(forUserEntryId id: UUID, _ attachment: WireAttachment) -> Bool {
        guard let entry = entries.last(where: { $0.id == id }), entry.isUser else {
            Logger.warning("ConversationLog: setAttachment — no user entry with id \(id.uuidString.prefix(8))", category: .ai)
            return false
        }
        userAttachments[id] = attachment
        return true
    }

    /// Record the context text appended after the last assistant entry's tool_results
    /// in the wire user message (called at tool-response send time).
    ///
    /// FIRST-WRITE-WINS (prompt-cache invariant): a stream-error retry rebuilds the
    /// request and recomputes the interview context, which contains time-varying
    /// content. The retry must replay the bytes the first attempt sent, so a
    /// recorded value is never overwritten (mirrors toolResultWireText semantics).
    func setToolContextTextForLastAssistantEntry(_ text: String) -> Bool {
        guard case .assistant(let id, _, _, _) = entries.last else {
            Logger.warning("ConversationLog: setToolContextTextForLastAssistantEntry — last entry is not an assistant message", category: .ai)
            return false
        }
        if let recorded = toolContextText[id] {
            if recorded != text {
                Logger.debug(
                    "ConversationLog: tool-turn context for entry \(id.uuidString.prefix(8)) already recorded — keeping original bytes (retry rebuild)",
                    category: .ai
                )
            }
            return true
        }
        toolContextText[id] = text
        return true
    }

    /// Record a wire-only user turn for a standalone coordinator message.
    /// These never appear in the UI transcript but must replay in history.
    func recordCoordinatorWireTurn(text: String) {
        coordinatorWireTurns.append((afterEntryId: entries.last?.id, text: text))
    }

    /// Snapshot the conversation in exact wire form for history replay.
    ///
    /// Called once per request build — this IS the serialization point, so it also
    /// records first-serialization state (tool_result wire strings) as a side effect.
    ///
    /// ORDERING INVARIANT (deterministic replay): for an assistant entry, the wire
    /// order is always assistant text/tool_use → tool_results → toolContextText →
    /// coordinator turns anchored on this entry (insertion order preserved). This is
    /// the same order the send paths produce (tool-response requests set
    /// toolContextText before building history; coordinator requests record their
    /// wire turn before building history), so a rebuilt history reproduces the
    /// previously sent prefix byte-for-byte.
    func getWireSnapshot() -> [WireEntry] {
        var result: [WireEntry] = []

        // Coordinator turns recorded before any entry existed
        for turn in coordinatorWireTurns where turn.afterEntryId == nil {
            result.append(.user(text: turn.text, attachment: nil))
        }

        for entry in entries {
            switch entry {
            case .user(let id, let text, _, _):
                result.append(.user(text: userWireText[id] ?? text, attachment: userAttachments[id]))
            case .assistant(let id, let text, let toolCalls, _):
                let wireCalls = toolCalls.map { calls in
                    calls.map { wireToolCall(for: $0) }
                }
                result.append(.assistant(
                    text: text,
                    toolCalls: wireCalls,
                    toolContextText: toolContextText[id]
                ))
            case .systemNote:
                break  // UI display only, never sent to the LLM
            }

            // Coordinator turns anchored after this entry (insertion order preserved)
            for turn in coordinatorWireTurns where turn.afterEntryId == entry.id {
                result.append(.user(text: turn.text, attachment: nil))
            }
        }

        return result
    }

    /// Resolve the exact tool_result wire string for a slot.
    ///
    /// First serialization records the string (the real result, or the pending
    /// placeholder if the tool hasn't finished). Rebuilds reuse the record
    /// UNCONDITIONALLY — recorded bytes are never mutated. A result that lands
    /// after its placeholder was serialized reaches the model via
    /// `pendingWireUpdates` tail delivery (see setToolResult). The old in-place
    /// "one-time bust" upgrade fired on nearly every slow UI tool and rewrote the
    /// entire cached suffix each time.
    private func wireToolCall(for slot: ToolCallSlot) -> WireToolCall {
        // Empty outputs are substituted HERE, not downstream, so the recorded
        // string is the exact wire string in all cases.
        let liveResult = slot.result.map { $0.isEmpty ? Self.emptyToolResultSubstitute : $0 }
        let resolved: String
        if let recorded = toolResultWireText[slot.callId] {
            resolved = recorded
        } else {
            let wire = liveResult ?? Self.pendingToolResultPlaceholder
            if liveResult == nil {
                Logger.debug("ConversationLog: tool_result \(slot.callId.prefix(8)) pending — serializing placeholder", category: .ai)
            }
            toolResultWireText[slot.callId] = wire
            resolved = wire
        }
        return WireToolCall(
            callId: slot.callId,
            name: slot.name,
            arguments: slot.arguments,
            result: resolved
        )
    }

    // MARK: - Late Tool-Result Tail Delivery

    /// Find a tool call slot anywhere in history (newest entry first).
    private func findSlot(callId: String) -> ToolCallSlot? {
        for entry in entries.reversed() {
            if case .assistant(_, _, let toolCalls?, _) = entry,
               let slot = toolCalls.first(where: { $0.callId == callId }) {
                return slot
            }
        }
        return nil
    }

    /// Queue a late tool result for delivery in the next request's volatile tail.
    /// Deduped by callId — the latest output wins.
    private func enqueueWireUpdate(callId: String, name: String, output: String, status: ToolCallStatus) {
        pendingWireUpdates.removeAll { $0.callId == callId }
        pendingWireUpdates.append(WireToolUpdate(callId: callId, name: name, output: output, status: status))
    }

    /// Drain queued late tool results at request-build time. The caller renders
    /// them into the request's volatile text, where they freeze into the wire
    /// history (first-write-wins) like all other tail content.
    func drainPendingWireUpdates() -> [WireToolUpdate] {
        let drained = pendingWireUpdates
        pendingWireUpdates.removeAll()
        return drained
    }

    // MARK: - Persistence Support

    /// Restore entries from persistence
    /// Removes any orphaned tool calls (tool_use without tool_result) to maintain Anthropic API invariant
    func restore(entries: [ConversationEntry]) {
        // CRITICAL: Remove orphaned tool calls from ALL entries on restore.
        // Anthropic API requires every tool_use to have a tool_result immediately after.
        // Instead of trying to synthetically fill orphaned slots (which has edge cases),
        // we simply remove the corrupted tool calls entirely - the conversation can
        // continue without them.
        self.entries = removeOrphanedToolCalls(from: entries)
        // Wire-text side tables are in-memory only; after restore the history
        // replays from display text (cache is cold after a restart anyway).
        userWireText.removeAll()
        userAttachments.removeAll()
        toolContextText.removeAll()
        toolResultWireText.removeAll()
        coordinatorWireTurns.removeAll()
        pendingWireUpdates.removeAll()
        Logger.info("ConversationLog: Restored \(self.entries.count) entries", category: .ai)
    }

    /// Remove orphaned tool calls from conversation history.
    /// An orphaned tool call is a ToolCallSlot where isResolved is false (no result was filled).
    /// These represent tool calls that were interrupted before completion.
    private func removeOrphanedToolCalls(from entries: [ConversationEntry]) -> [ConversationEntry] {
        guard !entries.isEmpty else { return [] }

        var result: [ConversationEntry] = []
        var totalRemoved = 0

        for (index, entry) in entries.enumerated() {
            switch entry {
            case .user, .systemNote:
                result.append(entry)

            case .assistant(let id, let text, let toolCalls, let timestamp):
                guard let toolCalls = toolCalls, !toolCalls.isEmpty else {
                    // No tool calls, keep as-is
                    result.append(entry)
                    continue
                }

                // Keep only tool calls that have their result filled (isResolved)
                let validToolCalls = toolCalls.filter { $0.isResolved }
                let orphanedCount = toolCalls.count - validToolCalls.count

                if orphanedCount > 0 {
                    let orphanedIds = toolCalls.filter { !$0.isResolved }
                        .map { String($0.callId.prefix(12)) }
                    Logger.warning("ConversationLog: Removing \(orphanedCount) orphaned tool call(s) from entry \(index): \(orphanedIds)", category: .ai)
                    totalRemoved += orphanedCount
                }

                // If no valid tool calls remain and text is empty, skip this entry entirely
                if validToolCalls.isEmpty && text.isEmpty {
                    Logger.warning("ConversationLog: Removing empty assistant entry \(index) (had only orphaned tool calls)", category: .ai)
                    // Coordinator wire turns anchored to the removed entry would
                    // otherwise vanish from every later replay (the model already
                    // saw them) — re-anchor to the nearest preceding survivor.
                    reanchorCoordinatorWireTurns(from: id, to: result.last?.id)
                    continue
                }

                // Rebuild the entry with only valid tool calls
                let cleanedEntry = ConversationEntry.assistant(
                    id: id,
                    text: text,
                    toolCalls: validToolCalls.isEmpty ? nil : validToolCalls,
                    timestamp: timestamp
                )
                result.append(cleanedEntry)
            }
        }

        if totalRemoved > 0 {
            Logger.info("ConversationLog: Removed \(totalRemoved) total orphaned tool call(s) from history", category: .ai)
        }

        return result
    }

    /// Re-anchor coordinator wire turns whose anchor entry is being removed by
    /// orphan cleanup, so wire turns the model has already seen keep replaying.
    /// Array insertion order is preserved, which keeps emission order
    /// chronological within the new anchor.
    private func reanchorCoordinatorWireTurns(from removedId: UUID, to survivorId: UUID?) {
        for index in coordinatorWireTurns.indices where coordinatorWireTurns[index].afterEntryId == removedId {
            coordinatorWireTurns[index].afterEntryId = survivorId
            Logger.info(
                "ConversationLog: re-anchored coordinator wire turn from removed entry \(removedId.uuidString.prefix(8))",
                category: .ai
            )
        }
    }

    /// Reset all state
    func reset() {
        entries.removeAll()
        userWireText.removeAll()
        userAttachments.removeAll()
        toolContextText.removeAll()
        toolResultWireText.removeAll()
        coordinatorWireTurns.removeAll()
        pendingWireUpdates.removeAll()
        Logger.info("ConversationLog: Reset", category: .ai)
    }

    /// Clean up any orphaned tool calls in the current conversation.
    /// Called when user stops processing mid-stream.
    func cleanupOrphanedToolCalls() {
        let beforeCount = entries.count
        entries = removeOrphanedToolCalls(from: entries)
        let afterCount = entries.count
        if beforeCount != afterCount {
            Logger.info("ConversationLog: Cleaned up entries (\(beforeCount) → \(afterCount))", category: .ai)
        }
    }

    // MARK: - System Notes

    /// Append an inline system note (displayed between bubbles, not as a bubble)
    /// Used for coordinator messages, agent completions, etc.
    func appendSystemNote(_ text: String) async {
        let entry = ConversationEntry.systemNote(
            id: UUID(),
            text: text,
            timestamp: Date()
        )
        entries.append(entry)
        Logger.info("ConversationLog: Appended system note", category: .ai)

        // Publish event for persistence
        await eventBus.publish(.llm(.conversationEntryAppended(entry: entry)))
    }

    // MARK: - UI Compatibility

    /// Convert entries to OnboardingMessage format for UI display
    /// This bridges ConversationLog to the existing UI layer
    func getMessagesForUI() -> [OnboardingMessage] {
        entries.compactMap { entry -> OnboardingMessage? in
            switch entry {
            case .user(let id, let text, let isSystemGenerated, let timestamp):
                return OnboardingMessage(
                    id: id,
                    role: .user,
                    text: text,
                    timestamp: timestamp,
                    isSystemGenerated: isSystemGenerated
                )
            case .assistant(let id, let text, let toolCalls, let timestamp):
                let uiToolCalls = toolCalls?.map { call in
                    OnboardingMessage.ToolCallInfo(
                        id: call.callId,
                        name: call.name,
                        arguments: call.arguments,
                        result: call.result
                    )
                }
                return OnboardingMessage(
                    id: id,
                    role: .assistant,
                    text: text,
                    timestamp: timestamp,
                    toolCalls: uiToolCalls
                )
            case .systemNote(let id, let text, let timestamp):
                return OnboardingMessage(
                    id: id,
                    role: .systemNote,
                    text: text,
                    timestamp: timestamp
                )
            }
        }
    }
}
