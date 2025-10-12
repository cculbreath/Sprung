//
//  TemplateEditorView+Preview.swift
//  Sprung
//

import AppKit
import Foundation
import PDFKit
import SwiftUI

extension TemplateEditorView {
    func closeEditor() {
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Template Editor" }) {
            window.close()
        }
    }

    func scheduleLivePreviewUpdate() {
        guard selectedTab == .pdfTemplate else { return }
        debounceTimer?.invalidate()

        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Task { @MainActor in
                await generateLivePreview()
            }
        }
    }

    @MainActor
    func generateInitialPreview() {
        guard selectedTab == .pdfTemplate else { return }
        Task {
            await generateLivePreview()
        }
    }

    @MainActor
    func generateLivePreview() async {
        guard selectedTab == .pdfTemplate, let resume = selectedResume else { return }

        if !isEditingCurrentTemplate || !assetHasChanges {
            previewPDFData = resume.pdfData
            return
        }

        isGeneratingLivePreview = true

        if assetHasChanges {
            _ = saveTemplate()
        }

        do {
            try await appEnvironment.resumeExportCoordinator.ensureFreshRenderedText(for: resume)
            previewPDFData = resume.pdfData
        } catch {
            Logger.error("Live preview generation failed: \(error)")
        }

        isGeneratingLivePreview = false
    }

    func prepareOverlayOptions() {
        overlayColorSelection = overlayColor
        overlayPageSelection = overlayPageIndex
        pendingOverlayDocument = overlayPDFDocument
        overlayPageCount = overlayPDFDocument?.pageCount ?? 0
        showOverlayOptionsSheet = true
    }

    func applyOverlaySelection() {
        if let pending = pendingOverlayDocument {
            overlayPDFDocument = pending
            let maxIndex = max(pending.pageCount - 1, 0)
            let clampedIndex = min(max(overlayPageSelection, 0), maxIndex)
            overlayPageIndex = clampedIndex
            overlayPageCount = pending.pageCount
            overlayFilename = pending.documentURL?.lastPathComponent ?? overlayFilename
            showOverlay = true
        } else if overlayPDFDocument != nil {
            let maxIndex = max((overlayPDFDocument?.pageCount ?? 1) - 1, 0)
            overlayPageIndex = min(max(overlayPageSelection, 0), maxIndex)
        }

        overlayColor = overlayColorSelection
        showOverlayOptionsSheet = false
    }

    func clearOverlaySelection() {
        overlayPDFDocument = nil
        pendingOverlayDocument = nil
        overlayPageCount = 0
        overlayFilename = nil
        overlayPageSelection = 0
        overlayPageIndex = 0
        showOverlay = false
    }

    func loadOverlayPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            saveError = "Failed to access overlay PDF"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = PDFDocument(url: url) else {
            saveError = "Failed to read overlay PDF"
            return
        }

        pendingOverlayDocument = document
        overlayPageCount = document.pageCount
        overlayPageSelection = min(overlayPageSelection, max(document.pageCount - 1, 0))
        overlayFilename = url.lastPathComponent
    }
}
