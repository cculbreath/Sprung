import AppKit
import CoreGraphics
import Foundation
import SwiftData
import SwiftOpenAI

// MARK: - Render Info

struct RevisionRenderInfo {
    let success: Bool
    let pageCount: Int
    let pdfData: Data?
}

// MARK: - Revision PDF Renderer

struct RevisionPDFRenderer {
    let workspaceService: ResumeRevisionWorkspaceService
    let pdfGenerator: NativePDFGenerator
    let modelContext: ModelContext

    /// Re-render the resume PDF from current workspace state.
    /// Returns render info including the PDF data for preview and page count.
    @MainActor
    func autoRenderResume(from resume: Resume) async -> RevisionRenderInfo {
        guard let workspacePath = workspaceService.workspacePath else {
            return RevisionRenderInfo(success: false, pageCount: 0, pdfData: nil)
        }

        do {
            let revisedNodes = try workspaceService.importRevisedTreeNodes()
            let revisedFontSizes = try workspaceService.importRevisedFontSizes()

            let tempResume = workspaceService.buildNewResume(
                from: resume,
                revisedNodes: revisedNodes,
                revisedFontSizes: revisedFontSizes,
                context: modelContext
            )

            let slug = resume.template?.slug ?? "default"
            let pdfData = try await pdfGenerator.generatePDF(for: tempResume, template: slug)

            // Write to workspace (so read_file can access it too)
            let pdfPath = workspacePath.appendingPathComponent("resume.pdf")
            try pdfData.write(to: pdfPath)

            let pageCount = Self.countPDFPages(pdfData)

            // Clean up temp resume
            modelContext.delete(tempResume)

            Logger.info("RevisionAgent: Auto-rendered PDF (\(pdfData.count) bytes, \(pageCount) pages)", category: .ai)
            return RevisionRenderInfo(success: true, pageCount: pageCount, pdfData: pdfData)
        } catch {
            Logger.error("RevisionAgent: Auto-render failed: \(error.localizedDescription)", category: .ai)
            return RevisionRenderInfo(success: false, pageCount: 0, pdfData: nil)
        }
    }

    /// Count the number of pages in a PDF data blob.
    static func countPDFPages(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            return 0
        }
        return document.numberOfPages
    }

    /// Render each page of a PDF to a JPEG image and return as Anthropic image content blocks.
    func renderPDFPageImages(_ pdfData: Data) -> [AnthropicContentBlock] {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider) else {
            return []
        }

        var blocks: [AnthropicContentBlock] = []
        let scale: CGFloat = 2.0 // 2x for readable text

        for pageIndex in 1...document.numberOfPages {
            guard let page = document.page(at: pageIndex) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)
            let width = Int(mediaBox.width * scale)
            let height = Int(mediaBox.height * scale)

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { continue }

            // White background
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Scale and draw
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)

            guard let cgImage = context.makeImage() else { continue }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                continue
            }

            let base64 = jpegData.base64EncodedString()
            let imageSource = AnthropicImageSource(mediaType: "image/jpeg", data: base64)
            let imageBlock = AnthropicImageBlock(source: imageSource)
            blocks.append(.image(imageBlock))
        }

        Logger.info("RevisionAgent: Rendered \(blocks.count) PDF page image(s) for agent preview", category: .ai)
        return blocks
    }
}
