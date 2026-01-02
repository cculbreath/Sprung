//
//  ParallelPageExtractor.swift
//  Sprung
//
//  Extracts text and graphics from PDF pages in parallel using LLM vision.
//  Respects configurable concurrency limit from Settings.
//

import Foundation

/// Extracts text and graphics from PDF pages in parallel using LLM vision.
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

    /// Extract text and graphics from multiple page images in parallel
    func extractPages(
        images: [URL],
        updateStatus: @escaping @MainActor @Sendable (String) async -> Void
    ) async throws -> [PageExtractionResult] {
        let totalPages = images.count
        var results: [Int: PageExtractionResult] = [:]
        var completedCount = 0
        let concurrency = maxConcurrency

        await updateStatus("Extracting text from \(totalPages) pages (max \(concurrency) concurrent)...")

        Logger.info("📄 ParallelPageExtractor: Starting extraction of \(totalPages) pages (concurrency: \(concurrency))", category: .ai)

        // Process pages in parallel with concurrency limit
        try await withThrowingTaskGroup(of: (Int, PageExtractionResult).self) { group in
            var pendingIndices = Array(0..<totalPages)
            var activeCount = 0

            // Seed initial batch
            while activeCount < concurrency && !pendingIndices.isEmpty {
                let index = pendingIndices.removeFirst()
                activeCount += 1

                group.addTask { [self] in
                    let result = try await self.extractSinglePage(
                        imageURL: images[index],
                        pageNumber: index + 1,
                        totalPages: totalPages
                    )
                    return (index, result)
                }
            }

            // Process results and add new tasks
            for try await (index, result) in group {
                results[index] = result
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
                        let result = try await self.extractSinglePage(
                            imageURL: images[nextIndex],
                            pageNumber: nextIndex + 1,
                            totalPages: totalPages
                        )
                        return (nextIndex, result)
                    }
                }
            }
        }

        Logger.info("📄 ParallelPageExtractor: Completed extraction of \(totalPages) pages", category: .ai)

        // Return results in page order
        let emptyResult = PageExtractionResult(
            text: "",
            graphics: PageGraphicsInfo(numberOfGraphics: 0, graphicsContent: [], qualitativeAssessment: [])
        )
        return (0..<totalPages).map { results[$0] ?? emptyResult }
    }

    /// Legacy method for backward compatibility - returns just text
    func extractPagesText(
        images: [URL],
        updateStatus: @escaping @MainActor @Sendable (String) async -> Void
    ) async throws -> [String] {
        let results = try await extractPages(images: images, updateStatus: updateStatus)
        return results.map { $0.text }
    }

    // MARK: - Single Page Extraction

    private func extractSinglePage(
        imageURL: URL,
        pageNumber: Int,
        totalPages: Int
    ) async throws -> PageExtractionResult {
        let imageData = try Data(contentsOf: imageURL)

        let prompt = """
        Extract ALL content from this document page (page \(pageNumber) of \(totalPages)).

        ## Text Extraction
        - Extract all visible text verbatim
        - Preserve structure: headings, paragraphs, lists, tables
        - For tables, use markdown table format
        - Maintain reading order

        ## Graphics Analysis
        For each diagram, chart, figure, image, or graphic on the page:
        1. Count the total number of graphics
        2. Describe what each graphic shows (the data, information, or content it conveys)
        3. Assess the quality/type of each graphic (e.g., "professional vector chart", "scanned photograph", "hand-drawn diagram", "screenshot", "infographic")

        If there are no graphics, return number_of_graphics: 0 with empty arrays.
        """

        // Use Gemini's structured output for guaranteed valid JSON
        let response = try await llmFacade.analyzeImagesWithGeminiStructured(
            images: [imageData],
            prompt: prompt,
            jsonSchema: PageExtractionResult.jsonSchema
        )

        // Parse structured response
        guard let data = response.data(using: .utf8) else {
            Logger.warning("📄 ParallelPageExtractor: Failed to parse page \(pageNumber) response", category: .ai)
            return PageExtractionResult(
                text: response,  // Fallback: treat entire response as text
                graphics: PageGraphicsInfo(numberOfGraphics: 0, graphicsContent: [], qualitativeAssessment: [])
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let result = try decoder.decode(PageExtractionResult.self, from: data)
            if result.graphics.numberOfGraphics > 0 {
                Logger.info("📄 Page \(pageNumber): \(result.text.count) chars, \(result.graphics.numberOfGraphics) graphics", category: .ai)
            }
            return result
        } catch {
            Logger.warning("📄 ParallelPageExtractor: JSON decode failed for page \(pageNumber): \(error.localizedDescription)", category: .ai)
            // Fallback: treat response as text
            return PageExtractionResult(
                text: response,
                graphics: PageGraphicsInfo(numberOfGraphics: 0, graphicsContent: [], qualitativeAssessment: [])
            )
        }
    }
}

// MARK: - Comparable Extension

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
