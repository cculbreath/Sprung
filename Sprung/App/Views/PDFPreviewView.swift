//
//  PDFPreviewView.swift
//  Sprung
//
//  PDF preview with overlay support for template editing
//
import SwiftUI
import PDFKit
import AppKit

final class PDFPreviewController: ObservableObject {
    @Published private(set) var canGoToNextPage: Bool = false
    @Published private(set) var canGoToPreviousPage: Bool = false

    weak var pdfView: PDFView? {
        didSet {
            guard let pdfView else { return }
            pdfView.displayMode = .singlePageContinuous
            pdfView.autoScales = true
            pdfView.minScaleFactor = 0.25
            pdfView.maxScaleFactor = 6.0
            updatePagingState()
        }
    }

    func attach(_ pdfView: PDFView) {
        if self.pdfView !== pdfView {
            self.pdfView = pdfView
        }
        updatePagingState()
    }

    func zoomIn() {
        pdfView?.zoomIn(nil)
    }

    func zoomOut() {
        pdfView?.zoomOut(nil)
    }

    func resetZoom() {
        pdfView?.autoScales = true
    }

    func goToNextPage() {
        pdfView?.goToNextPage(nil)
        updatePagingState()
    }

    func goToPreviousPage() {
        pdfView?.goToPreviousPage(nil)
        updatePagingState()
    }

    func goToPage(at index: Int) {
        guard let document = pdfView?.document,
              index >= 0, index < document.pageCount,
              let page = document.page(at: index) else { return }
        pdfView?.go(to: page)
        updatePagingState()
    }

    func updatePagingState() {
        let next = pdfView?.canGoToNextPage ?? false
        let previous = pdfView?.canGoToPreviousPage ?? false
        DispatchQueue.main.async {
            self.canGoToNextPage = next
            self.canGoToPreviousPage = previous
        }
    }
}

struct PDFPreviewView: NSViewRepresentable {
    let pdfData: Data
    let overlayDocument: PDFDocument?
    let overlayPageIndex: Int
    let overlayOpacity: Double
    let overlayColor: NSColor
    let controller: PDFPreviewController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = NSColor.textBackgroundColor
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 6.0
        controller.attach(pdfView)
        context.coordinator.startObserving(pdfView: pdfView)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        controller.attach(nsView)

        if let merged = mergedDocument() {
            nsView.document = merged
        } else {
            nsView.document = PDFDocument(data: pdfData)
        }
        controller.updatePagingState()
    }

    private func mergedDocument() -> PDFDocument? {
        guard let overlayDocument,
              let mainPDF = PDFDocument(data: pdfData) else {
            return nil
        }

        let merged = PDFDocument()
        for index in 0..<mainPDF.pageCount {
            guard let mainPage = mainPDF.page(at: index) else { continue }
            let targetBounds = mainPage.bounds(for: .mediaBox)

            let image = NSImage(size: targetBounds.size)
            image.lockFocusFlipped(false)
            guard let context = NSGraphicsContext.current?.cgContext else {
                image.unlockFocus()
                continue
            }

            context.saveGState()
            mainPage.draw(with: .mediaBox, to: context)
            context.restoreGState()

            if let overlayPage = overlayDocument.page(at: overlayPageIndex) ?? overlayDocument.page(at: 0) {
                drawOverlay(
                    overlayPage: overlayPage,
                    in: context,
                    targetBounds: targetBounds,
                    opacity: overlayOpacity,
                    color: overlayColor
                )
            }

            image.unlockFocus()

            if let newPage = PDFPage(image: image) {
                merged.insert(newPage, at: merged.pageCount)
            }
        }

        return merged
    }

    private func drawOverlay(
        overlayPage: PDFPage,
        in context: CGContext,
        targetBounds: CGRect,
        opacity: Double,
        color: NSColor
    ) {
        guard let cgPage = overlayPage.pageRef else { return }
        let overlayBounds = cgPage.getBoxRect(.mediaBox)
        let scaleX = targetBounds.width / overlayBounds.width
        let scaleY = targetBounds.height / overlayBounds.height

        context.saveGState()
        context.translateBy(x: 0, y: targetBounds.height)
        context.scaleBy(x: 1, y: -1)

        var transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        transform = transform.translatedBy(x: 0, y: -overlayBounds.height)
        context.concatenate(transform)

        context.drawPDFPage(cgPage)
        context.setBlendMode(.sourceAtop)
        let overlayColor = color.withAlphaComponent(CGFloat(opacity))
        context.setFillColor(overlayColor.cgColor)
        context.fill(CGRect(origin: .zero, size: overlayBounds.size))
        context.restoreGState()
    }

    final class Coordinator: NSObject {
        private var observationTokens: [Any] = []
        private let parent: PDFPreviewView

        init(parent: PDFPreviewView) {
            self.parent = parent
        }

        func startObserving(pdfView: PDFView) {
            stopObserving()
            let center = NotificationCenter.default
            let controller = parent.controller
            let pageToken = center.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { _ in
                controller.updatePagingState()
            }
            let zoomToken = center.addObserver(
                forName: Notification.Name.PDFViewScaleChanged,
                object: pdfView,
                queue: .main
            ) { _ in
                controller.updatePagingState()
            }
            observationTokens = [pageToken, zoomToken]
        }

        func stopObserving() {
            let center = NotificationCenter.default
            observationTokens.forEach { center.removeObserver($0) }
            observationTokens.removeAll()
        }

        deinit {
            stopObserving()
        }
    }
}
