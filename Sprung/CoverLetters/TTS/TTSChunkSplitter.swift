//
//  TTSChunkSplitter.swift
//  Sprung
//
//  Pure text-prep helpers for TTS: sentence-based chunking, length truncation,
//  and markdown stripping. Extracted from OpenAITTSProvider / TTSViewModel so
//  they can be unit-tested without the audio/streaming machinery.
//

import Foundation

enum TTSChunkSplitter {

    /// Split text into chunks no larger than `maxLength`, breaking on sentence
    /// boundaries. Note: sentences are split on any of `.!?` but each is
    /// re-terminated with `". "`, so `?`/`!` terminators become `.` — a known
    /// quirk preserved from the original implementation.
    static func splitIntoChunks(_ text: String, maxLength: Int = 4000) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        for sentence in sentences {
            let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSentence.isEmpty { continue }
            // Add back the punctuation if it was removed
            let fullSentence = trimmedSentence + ". "
            // If adding this sentence would exceed the limit, save current chunk and start new one
            if !currentChunk.isEmpty && currentChunk.count + fullSentence.count > maxLength {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                currentChunk = fullSentence
            } else {
                currentChunk += fullSentence
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
        }
        return chunks
    }

    /// Truncate `text` to at most `maxLength` characters, preferring to cut at the
    /// last word boundary and appending an ellipsis. Returns `text` unchanged when
    /// it is already within the limit.
    static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let truncated = String(text.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        } else {
            return truncated + "..."
        }
    }

    /// Strip lightweight markdown markers (`#`, `**`, `*`) so they are not read
    /// aloud, and trim surrounding whitespace.
    static func cleanMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
