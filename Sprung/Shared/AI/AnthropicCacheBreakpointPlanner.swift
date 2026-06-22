//
//  AnthropicCacheBreakpointPlanner.swift
//  Sprung
//
//  Shared message-tier prompt-cache breakpoint placement for Anthropic Messages
//  API requests. Extracted from the two near-verbatim copies that previously
//  lived in AnthropicRequestBuilder (onboarding interview) and ResumeRevisionAgent
//  (resume revision): the same BlockPosition geometry, isMarkable rule,
//  >20-block lookback anchor, hard clamp, and block-rewriting switch.
//
//  ⚠️ BYTE-SENSITIVE — this is the prompt-cache replay surface. Output MUST stay
//  byte-identical to the original two implementations. Verified by
//  AnthropicCacheBreakpointPlannerTests (clamp + addingCacheControl + BlockPosition +
//  plan) and the CachePrefixAuditor "📉 PREFIX DIVERGENCE" check + the replay suite.
//  Do NOT change placement logic without re-running `xcodebuild test`.
//
//  Applied at request-build time ONLY — placements are NEVER persisted, so they
//  move naturally as the conversation grows. The API matches cache prefixes on
//  prompt content and ignores cache_control placement for prefix matching, so
//  moving breakpoints between turns does not invalidate earlier cache entries.
//
//  The two callers differ in exactly two parameters, captured by this value
//  type:
//  - cacheControl: TTL — .ephemeral (5m default) for onboarding; 1h for the
//    human-in-the-loop revision session (idle review gaps exceed 5m).
//  - reservedBreakpointCount: breakpoints consumed OUTSIDE the message tier,
//    against Anthropic's hard limit of 4 cache_control blocks per request.
//    Onboarding reserves the system block (0 or 1); revision reserves the
//    last-tool breakpoint plus the system block (2).
//
//  Both callers place ONLY the moving tail + >20-block lookback breakpoints, which
//  advance with the conversation every turn. A large early payload (the onboarding
//  resume PDF, the revision cover-letter PDF) rides inside the cached prefix the
//  moving chain extends over — it does NOT get its own breakpoint. An early FIXED
//  breakpoint actively strands the cache: once the moving breakpoints drift >20
//  blocks past it, Anthropic's ~20-block lookback can no longer bridge the gap, so
//  the read pins at the payload while the entire growing tail re-writes every turn.
//  (Onboarding previously planted a fixed breakpoint on the last document block;
//  removing it is what lets the read track the conversation instead of pinning.)
//

import Foundation
import SwiftOpenAI

/// Pure placement of message-tier prompt-cache breakpoints. Same assembled
/// message array ⇒ same placement (the ACCEPTANCE INVARIANT both callers rely on).
struct AnthropicCacheBreakpointPlanner {

    /// Position of a content block in the assembled message array.
    struct BlockPosition: Equatable {
        let messageIndex: Int
        let blockIndex: Int
    }

    /// Cache-control directive attached to every breakpoint this planner plants.
    let cacheControl: AnthropicCacheControl
    /// Breakpoints consumed before the message tier (system, tools) — counted
    /// against Anthropic's hard limit of 4 cache_control blocks per request.
    let reservedBreakpointCount: Int

    /// Plant message-tier cache breakpoints on a per-request copy of `messages`.
    /// The stored history is never mutated (byte-stability invariant), so the
    /// breakpoints move naturally each turn and turn N+1 reads the prefix turn N
    /// wrote.
    ///
    /// Candidates, in priority order:
    /// 1. Tail — last markable block of the final message (incremental
    ///    conversation caching: the prefix the previous turn wrote).
    /// 2. Lookback (conditional, totalBlocks > 20) — last markable block of the
    ///    latest message that ends ≥20 blocks before the end, so the next turn's
    ///    tail breakpoint always finds a prior cache entry inside Anthropic's
    ///    ~20-block lookback window after tool-heavy turns.
    func plan(messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return messages }

        // Flatten block geometry (string content counts as one text block).
        let blocksByMessage: [[AnthropicContentBlock]] = messages.map { Self.contentBlocks(of: $0) }
        var flatStartIndex: [Int] = []
        var totalBlocks = 0
        for blocks in blocksByMessage {
            flatStartIndex.append(totalBlocks)
            totalBlocks += blocks.count
        }

        func isMarkable(_ block: AnthropicContentBlock) -> Bool {
            if case .toolUse = block { return false }
            return true
        }

        func lastMarkableBlock(inMessage messageIndex: Int) -> BlockPosition? {
            for blockIndex in blocksByMessage[messageIndex].indices.reversed()
            where isMarkable(blocksByMessage[messageIndex][blockIndex]) {
                return BlockPosition(messageIndex: messageIndex, blockIndex: blockIndex)
            }
            return nil
        }

        // Tail — last markable block of the final message (walking back if the
        // final message has none: tool_use blocks cannot carry cache_control).
        var tail: BlockPosition?
        for messageIndex in blocksByMessage.indices.reversed() {
            if let position = lastMarkableBlock(inMessage: messageIndex) {
                tail = position
                break
            }
        }

        // Lookback (conditional) — Anthropic's cache lookback walks at most 20
        // content blocks back from a breakpoint. After tool-heavy turns a single
        // turn can add >20 blocks, so plant one boundary on the last markable
        // block of the latest message that ends at least 20 blocks before the end
        // of the array. Deterministic rule: same history ⇒ same placement.
        var lookback: BlockPosition?
        if totalBlocks > 20 {
            for messageIndex in blocksByMessage.indices.reversed() {
                let lastFlatIndex = flatStartIndex[messageIndex] + blocksByMessage[messageIndex].count - 1
                guard totalBlocks - 1 - lastFlatIndex >= 20 else { continue }
                if let position = lastMarkableBlock(inMessage: messageIndex) {
                    lookback = position
                    break
                }
            }
        }

        let kept = Self.clampBreakpointCandidates(
            [tail, lookback],
            reservedBreakpointCount: reservedBreakpointCount
        )
        guard !kept.isEmpty else { return messages }

        // Apply marks, grouping by message so multiple marks in one message stack.
        var marksByMessage: [Int: [Int]] = [:]
        for position in kept {
            marksByMessage[position.messageIndex, default: []].append(position.blockIndex)
        }

        var result = messages
        for (messageIndex, blockIndexes) in marksByMessage {
            var blocks = blocksByMessage[messageIndex]
            for blockIndex in blockIndexes {
                guard let marked = Self.addingCacheControl(to: blocks[blockIndex], cacheControl: cacheControl) else { continue }
                blocks[blockIndex] = marked
            }
            result[messageIndex] = AnthropicMessage(role: messages[messageIndex].role, content: .blocks(blocks))
        }

        Logger.debug(
            "📍 Cache breakpoints: reserved=\(reservedBreakpointCount), message=\(kept.count) " +
            "(tail=\(tail != nil), lookback=\(lookback != nil)), " +
            "blocks=\(totalBlocks)",
            category: .ai
        )

        return result
    }

    // MARK: - Pure helpers (inspectable in isolation; covered by AnthropicCacheBreakpointPlannerTests)

    /// Flatten a message into content blocks (string content ⇒ one text block).
    static func contentBlocks(of message: AnthropicMessage) -> [AnthropicContentBlock] {
        switch message.content {
        case .text(let text):
            return [.text(AnthropicTextBlock(text: text))]
        case .blocks(let blocks):
            return blocks
        }
    }

    /// HARD CLAMP — Anthropic allows at most 4 cache_control blocks per request,
    /// INCLUDING reserved (system / tool) breakpoints. With `reservedBreakpointCount`
    /// counted, at most (4 - reserved) message breakpoints may survive. `candidates`
    /// are supplied in priority order (tail, then lookback), so on overflow the
    /// lowest-priority breakpoint is dropped first; the first (tail) breakpoint
    /// always survives. Nil candidates are skipped and duplicate positions collapse.
    /// Taking an ordered array (rather than fixed named slots) keeps the now-free
    /// 4th breakpoint addable without a signature change. Pure function so the
    /// invariant is inspectable in isolation.
    static func clampBreakpointCandidates(
        _ candidates: [BlockPosition?],
        reservedBreakpointCount: Int
    ) -> [BlockPosition] {
        let budget = max(0, 4 - reservedBreakpointCount)
        var kept: [BlockPosition] = []
        for candidate in candidates {
            guard let candidate, !kept.contains(candidate) else { continue }
            guard kept.count < budget else { break }
            kept.append(candidate)
        }
        return kept
    }

    /// Rebuild a content block with `cacheControl` attached. Returns nil for block
    /// kinds that cannot carry cache_control (tool_use in the fork's types) —
    /// placement skips those.
    static func addingCacheControl(
        to block: AnthropicContentBlock,
        cacheControl: AnthropicCacheControl
    ) -> AnthropicContentBlock? {
        switch block {
        case .text(let textBlock):
            return .text(AnthropicTextBlock(text: textBlock.text, cacheControl: cacheControl))
        case .image(let imageBlock):
            return .image(AnthropicImageBlock(source: imageBlock.source, cacheControl: cacheControl))
        case .document(let documentBlock):
            return .document(AnthropicDocumentBlock(source: documentBlock.source, cacheControl: cacheControl))
        case .toolResult(let resultBlock):
            return .toolResult(AnthropicToolResultBlock(
                toolUseId: resultBlock.toolUseId,
                content: resultBlock.content,
                isError: resultBlock.isError ?? false,
                cacheControl: cacheControl
            ))
        case .toolUse:
            return nil
        }
    }
}
