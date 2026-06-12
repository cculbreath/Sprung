//
//  CachePrefixAuditor.swift
//  Sprung
//
//  Diagnostic tripwire for the prompt-cache byte-stability invariant.
//
//  Anthropic prompt caching is a prefix match over the rendered request
//  (tools → system → messages): one changed byte invalidates everything after
//  it, silently re-billing the whole suffix as cache writes (1.25x input cost).
//  The June 2026 session that cost ~$40 had a 24% hit rate because tool_result
//  placeholders were upgraded in place 26 times, each rewrite invisible until
//  the usage totals came in.
//
//  This auditor fingerprints every outgoing interview request as a sequence of
//  canonical content chunks (one per tool / system prompt / content block),
//  compares against the previous request, and logs the FIRST divergent chunk
//  with both old and new content heads — naming the exact mutation instead of
//  leaving a token-count mystery.
//
//  Reading the log:
//  - "🧭 CacheAudit: prefix intact" — history replayed byte-identically.
//  - "🧭 CacheAudit: ⚠️ PREFIX DIVERGENCE" — the invariant broke; the logged
//    chunk identifies the offending block. Phase transitions legitimately log
//    one divergence at chunk 0 (tools+system swap).
//
//  Canonicalization ignores cache_control placement (the API ignores it for
//  prefix matching too), and hashes large payloads (images/documents) instead
//  of storing them.
//

import CryptoKit
import Foundation
import SwiftOpenAI

/// Fingerprints outgoing Anthropic requests and logs the first divergent
/// content chunk between consecutive requests. One instance per conversation
/// stream (request builds are serialized; the lock is belt-and-braces).
final class CachePrefixAuditor: @unchecked Sendable {

    private struct Chunk {
        /// Human-readable position label, e.g. "msg[4].user.tool_result(toolu_01Ab…)"
        let label: String
        /// SHA-256 over the canonical content bytes (hex prefix)
        let hash: String
        /// First characters of the canonical content, for divergence logs
        let head: String
    }

    private let lock = NSLock()
    private var previous: [Chunk] = []
    private var requestIndex = 0

    // MARK: - Audit

    /// Fingerprint a fully-assembled request and log how its prefix compares to
    /// the previous request on this stream.
    func audit(tools: [AnthropicTool], system: String?, messages: [AnthropicMessage]) {
        let chunks = Self.fingerprint(tools: tools, system: system, messages: messages)

        lock.lock()
        let prior = previous
        let index = requestIndex
        previous = chunks
        requestIndex += 1
        lock.unlock()

        guard index > 0 else {
            Logger.info("🧭 CacheAudit #0: baseline recorded (\(chunks.count) chunks)", category: .ai)
            return
        }

        var matched = 0
        while matched < prior.count && matched < chunks.count
            && prior[matched].hash == chunks[matched].hash {
            matched += 1
        }

        if matched == prior.count {
            Logger.info(
                "🧭 CacheAudit #\(index): prefix intact — matched all \(prior.count) prior chunks, +\(chunks.count - matched) appended",
                category: .ai
            )
            return
        }

        let invalidated = prior.count - matched
        let old = prior[matched]
        let new = matched < chunks.count
            ? "[\(chunks[matched].hash)] \(chunks[matched].label): \(chunks[matched].head)"
            : "(request is SHORTER than its predecessor — history truncated)"
        Logger.warning(
            """
            🧭 CacheAudit #\(index): ⚠️ PREFIX DIVERGENCE at chunk \(matched)/\(prior.count) — \(invalidated) previously-sent chunk(s) invalidated (entire suffix re-billed as cache writes)
              was [\(old.hash)] \(old.label): \(old.head)
              now \(new)
            """,
            category: .ai
        )
    }

    // MARK: - Canonical Fingerprinting

    private static func fingerprint(
        tools: [AnthropicTool],
        system: String?,
        messages: [AnthropicMessage]
    ) -> [Chunk] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var chunks: [Chunk] = []

        // Tools render first in the prompt — one chunk per tool.
        for (index, tool) in tools.enumerated() {
            let canonical: String
            if let data = try? encoder.encode(tool), let json = String(data: data, encoding: .utf8) {
                canonical = json
            } else {
                canonical = "unencodable-tool"
            }
            chunks.append(makeChunk(label: "tool[\(index)]", content: canonical))
        }

        // System prompt (cache_control placement deliberately excluded).
        if let system, !system.isEmpty {
            chunks.append(makeChunk(label: "system", content: system))
        }

        // Message content blocks, one chunk per block.
        for (messageIndex, message) in messages.enumerated() {
            let blocks: [AnthropicContentBlock]
            switch message.content {
            case .text(let text):
                blocks = [.text(AnthropicTextBlock(text: text))]
            case .blocks(let contentBlocks):
                blocks = contentBlocks
            }
            for block in blocks {
                let (kind, canonical) = canonicalize(block, encoder: encoder)
                chunks.append(makeChunk(
                    label: "msg[\(messageIndex)].\(message.role).\(kind)",
                    content: canonical
                ))
            }
        }

        return chunks
    }

    /// Canonical content string for a block, ignoring cache_control.
    private static func canonicalize(
        _ block: AnthropicContentBlock,
        encoder: JSONEncoder
    ) -> (kind: String, content: String) {
        switch block {
        case .text(let textBlock):
            return ("text", textBlock.text)
        case .image(let imageBlock):
            return ("image", "\(imageBlock.source.mediaType)|\(imageBlock.source.data)")
        case .document(let documentBlock):
            let source = (try? encoder.encode(documentBlock.source))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "unencodable-document"
            return ("document", source)
        case .toolUse(let toolUse):
            let input = (try? encoder.encode(toolUse.input))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "unencodable-input"
            return ("tool_use(\(toolUse.id.prefix(12))…)", "\(toolUse.id)|\(toolUse.name)|\(input)")
        case .toolResult(let toolResult):
            return (
                "tool_result(\(toolResult.toolUseId.prefix(12))…)",
                "\(toolResult.toolUseId)|\(toolResult.isError ?? false)|\(toolResult.content)"
            )
        }
    }

    private static func makeChunk(label: String, content: String) -> Chunk {
        let digest = SHA256.hash(data: Data(content.utf8))
        let hash = digest.prefix(5).map { String(format: "%02x", $0) }.joined()
        let head = String(content.prefix(90))
            .replacingOccurrences(of: "\n", with: "⏎")
        return Chunk(label: label, hash: hash, head: head)
    }
}
