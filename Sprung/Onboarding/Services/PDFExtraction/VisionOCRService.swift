//
//  VisionOCRService.swift
//  Sprung
//
//  Native OCR using Apple's Vision framework.
//  No external dependencies - uses on-device ML models.
//

import Foundation
import Vision
import AppKit

/// Native OCR using Apple's Vision framework.
actor VisionOCRService {

    /// Recognition level for accuracy vs speed tradeoff
    enum RecognitionLevel {
        case fast       // VNRequestTextRecognitionLevel.fast
        case accurate   // VNRequestTextRecognitionLevel.accurate
    }

    private let recognitionLevel: RecognitionLevel

    init(recognitionLevel: RecognitionLevel = .accurate) {
        self.recognitionLevel = recognitionLevel
    }

    // MARK: - OCR Methods

    /// OCR a single image file
    func recognizeImage(_ imageURL: URL) async throws -> String {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageLoadFailed
        }

        return try await recognizeCGImage(cgImage)
    }

    /// OCR a CGImage directly
    func recognizeCGImage(_ cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                // Extract text from observations, sorted by position (top to bottom, left to right)
                let sortedObservations = observations.sorted { obs1, obs2 in
                    // Sort by Y position (top first), then X position (left first)
                    // Note: Vision uses normalized coordinates with origin at bottom-left
                    if abs(obs1.boundingBox.midY - obs2.boundingBox.midY) > 0.01 {
                        return obs1.boundingBox.midY > obs2.boundingBox.midY  // Higher Y = higher on page
                    }
                    return obs1.boundingBox.midX < obs2.boundingBox.midX
                }

                let text = sortedObservations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            // Configure request
            request.recognitionLevel = recognitionLevel == .accurate ? .accurate : .fast
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]  // Can be expanded

            // Perform request
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    /// OCR multiple images with progress callback
    func recognizeImages(
        _ imageURLs: [URL],
        progressHandler: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> String {
        var results: [String] = []
        let total = imageURLs.count

        for (index, url) in imageURLs.enumerated() {
            let text = try await recognizeImage(url)
            results.append("--- Page \(index + 1) ---\n\(text)")
            await progressHandler?(index + 1, total)
        }

        return results.joined(separator: "\n\n")
    }

    // MARK: - Error Types

    enum OCRError: Error, LocalizedError {
        case imageLoadFailed
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .imageLoadFailed:
                return "Failed to load image for OCR"
            case .recognitionFailed(let reason):
                return "OCR recognition failed: \(reason)"
            }
        }
    }
}
