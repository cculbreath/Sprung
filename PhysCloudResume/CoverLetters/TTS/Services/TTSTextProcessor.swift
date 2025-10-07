// PhysCloudResume/CoverLetters/TTS/Services/TTSTextProcessor.swift

import Foundation

/// Handles text processing and chunking for TTS operations
class TTSTextProcessor {
    
    // MARK: - Configuration
    
    private static let defaultMaxLength = 4000 // Leave buffer below OpenAI's 4096 limit
    private static let absoluteMaxLength = 4096 // OpenAI TTS hard limit
    
    // MARK: - Text Validation and Preparation
    
    /// Validates and prepares text for TTS processing
    /// - Parameter text: The input text
    /// - Returns: Processed text ready for TTS
    static func prepareTextForTTS(_ text: String) -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanText.isEmpty else {
            Logger.warning("Empty text provided for TTS")
            return ""
        }
        
        // Check if text exceeds the absolute limit
        if cleanText.count > absoluteMaxLength {
            Logger.warning("Text length (\(cleanText.count)) exceeds TTS limit (\(absoluteMaxLength)). Truncating...")
            return truncateTextAtWordBoundary(cleanText, maxLength: absoluteMaxLength)
        }
        
        return cleanText
    }
    
    /// Splits text into chunks suitable for TTS streaming
    /// - Parameters:
    ///   - text: The text to split
    ///   - maxLength: Maximum length per chunk
    /// - Returns: Array of text chunks
    static func splitTextIntoChunks(_ text: String, maxLength: Int = defaultMaxLength) -> [String] {
        let preparedText = prepareTextForTTS(text)
        
        guard !preparedText.isEmpty else {
            return []
        }
        
        // If text is short enough for a single chunk, return it as-is
        if preparedText.count <= maxLength {
            return [preparedText]
        }
        
        Logger.debug("Splitting text (\(preparedText.count) chars) into chunks (max \(maxLength) chars each)")
        
        var chunks: [String] = []
        var currentChunk = ""
        
        // Split by sentences for better natural breaks
        let sentences = splitIntoSentences(preparedText)
        
        for sentence in sentences {
            let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSentence.isEmpty { continue }
            
            // Ensure the sentence itself isn't too long
            let processedSentence = ensureSentenceLength(trimmedSentence, maxLength: maxLength)
            
            // If adding this sentence would exceed the limit, save current chunk and start new one
            if !currentChunk.isEmpty && currentChunk.count + processedSentence.count + 1 > maxLength {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                currentChunk = processedSentence
            } else {
                if !currentChunk.isEmpty {
                    currentChunk += " "
                }
                currentChunk += processedSentence
            }
        }
        
        // Add any remaining text
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
        }
        
        Logger.debug("Split text into \(chunks.count) chunks. Lengths: \(chunks.map { $0.count })")
        return chunks
    }
    
    // MARK: - Private Helper Methods
    
    /// Truncates text at word boundary if possible
    /// - Parameters:
    ///   - text: The text to truncate
    ///   - maxLength: Maximum allowed length
    /// - Returns: Truncated text
    private static func truncateTextAtWordBoundary(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        
        let truncated = String(text.prefix(maxLength - 3)) // Leave room for "..."
        
        // Try to find a word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            let result = String(truncated[..<lastSpace]) + "..."
            Logger.debug("Truncated text to \(result.count) characters at word boundary")
            return result
        } else {
            let result = truncated + "..."
            Logger.debug("Truncated text to \(result.count) characters (no word boundary found)")
            return result
        }
    }
    
    /// Splits text into sentences using common sentence endings
    /// - Parameter text: The text to split
    /// - Returns: Array of sentences
    private static func splitIntoSentences(_ text: String) -> [String] {
        // Enhanced sentence splitting with better punctuation handling
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        var sentences: [String] = []
        var currentSentence = ""
        var i = text.startIndex
        
        while i < text.endIndex {
            let char = text[i]
            currentSentence.append(char)
            
            // Check if this is a sentence ender
            if let scalar = char.unicodeScalars.first, sentenceEnders.contains(scalar) {
                // Look ahead to see if there's more content
                let nextIndex = text.index(after: i)
                if nextIndex < text.endIndex {
                    let nextChar = text[nextIndex]
                    // If next character is whitespace or end of text, this is likely a sentence boundary
                    if nextChar.isWhitespace || nextIndex == text.index(before: text.endIndex) {
                        sentences.append(currentSentence)
                        currentSentence = ""
                    }
                } else {
                    // End of text
                    sentences.append(currentSentence)
                    currentSentence = ""
                }
            }
            
            i = text.index(after: i)
        }
        
        // Add any remaining text
        if !currentSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(currentSentence)
        }
        
        // Filter out empty sentences and clean up
        let cleanedSentences = sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return cleanedSentences
    }
    
    /// Ensures a sentence doesn't exceed the maximum length
    /// - Parameters:
    ///   - sentence: The sentence to check
    ///   - maxLength: Maximum allowed length
    /// - Returns: Processed sentence
    private static func ensureSentenceLength(_ sentence: String, maxLength: Int) -> String {
        guard sentence.count > maxLength else { return sentence }
        
        Logger.warning("Sentence too long (\(sentence.count) chars), truncating")
        return truncateTextAtWordBoundary(sentence, maxLength: maxLength)
    }
    
    // MARK: - Text Analysis
    
    /// Estimates the audio duration for a given text
    /// - Parameter text: The text to analyze
    /// - Returns: Estimated duration in seconds (rough approximation)
    static func estimateAudioDuration(_ text: String) -> TimeInterval {
        let wordsPerMinute: Double = 180 // Average speaking rate
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let estimatedMinutes = Double(wordCount) / wordsPerMinute
        return estimatedMinutes * 60.0
    }
    
    /// Gets word count for a text
    /// - Parameter text: The text to analyze
    /// - Returns: Number of words
    static func getWordCount(_ text: String) -> Int {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    
    /// Checks if text requires chunking
    /// - Parameters:
    ///   - text: The text to check
    ///   - maxLength: Maximum length for single chunk
    /// - Returns: True if text needs to be chunked
    static func requiresChunking(_ text: String, maxLength: Int = defaultMaxLength) -> Bool {
        return prepareTextForTTS(text).count > maxLength
    }
}
