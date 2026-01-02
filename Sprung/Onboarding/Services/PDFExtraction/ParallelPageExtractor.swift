//
//  ParallelPageExtractor.swift
//  Sprung
//
//  Extracts text from PDF pages in parallel using LLM vision.
//  Respects configurable concurrency limit from Settings.
//

import Foundation

/// Extracts text from PDF pages in parallel using LLM vision.
actor ParallelPageExtractor {

    private let llmFacade: LLMFacade

    /// Max concurrent LLM calls - from UserDefaults
    private var maxConcurrency: Int {
        let value = UserDefaults.standard.integer(forKey: "maxConcurrentPDFExtractions")
        return (value > 0 ? value : 4).clamped(to: 1...10)
    }

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    // MARK: - Extraction

    /// Extract text from multiple page images in parallel
    func extractPages(
        images: [URL],
        updateStatus: @escaping @MainActor @Sendable (String) async -> Void
    ) async throws -> [String] {
        let totalPages = images.count
        var results: [Int: String] = [:]
        var completedCount = 0
        let concurrency = maxConcurrency

        await updateStatus("Extracting text from \(totalPages) pages (max \(concurrency) concurrent)...")

        Logger.info("📄 ParallelPageExtractor: Starting extraction of \(totalPages) pages (concurrency: \(concurrency))", category: .ai)

        // Process pages in parallel with concurrency limit
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var pendingIndices = Array(0..<totalPages)
            var activeCount = 0

            // Seed initial batch
            while activeCount < concurrency && !pendingIndices.isEmpty {
                let index = pendingIndices.removeFirst()
                activeCount += 1

                group.addTask { [self] in
                    let text = try await self.extractSinglePage(
                        imageURL: images[index],
                        pageNumber: index + 1,
                        totalPages: totalPages
                    )
                    return (index, text)
                }
            }

            // Process results and add new tasks
            for try await (index, text) in group {
                results[index] = text
                completedCount += 1
                activeCount -= 1

                // Update status
                let percent = Int((Double(completedCount) / Double(totalPages)) * 100)
                await updateStatus("Extracted \(completedCount)/\(totalPages) pages (\(percent)%)")

                // Add next page if available
                if !pendingIndices.isEmpty {
                    let nextIndex = pendingIndices.removeFirst()
                    activeCount += 1

                    group.addTask { [self] in
                        let text = try await self.extractSinglePage(
                            imageURL: images[nextIndex],
                            pageNumber: nextIndex + 1,
                            totalPages: totalPages
                        )
                        return (nextIndex, text)
                    }
                }
            }
        }

        Logger.info("📄 ParallelPageExtractor: Completed extraction of \(totalPages) pages", category: .ai)

        // Return results in page order
        return (0..<totalPages).map { results[$0] ?? "" }
    }

    // MARK: - Single Page Extraction

    private func extractSinglePage(
        imageURL: URL,
        pageNumber: Int,
        totalPages: Int
    ) async throws -> String {
        let imageData = try Data(contentsOf: imageURL)

        let prompt = """
        Extract ALL text from this document page (page \(pageNumber) of \(totalPages)).
        Preserve structure: headings, paragraphs, lists, tables.
        For tables, use markdown format.
        Output only the extracted text, no commentary.
        """

        // Use Gemini's native vision API (model configured in Settings)
        let text = try await llmFacade.analyzeImagesWithGemini(
            images: [imageData],
            prompt: prompt
        )

        return text
    }
}

// MARK: - Comparable Extension

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
