//
//  PDFPreviewView.swift
//  PhysCloudResume
//
//  PDF preview with overlay support for template editing
//

import SwiftUI
import PDFKit
import AppKit

struct PDFPreviewView: NSViewRepresentable {
    let pdfData: Data
    let overlayPDFData: Data?
    let overlayOpacity: Double
    
    func makeNSView(context: Context) -> CustomPDFView {
        let customPDFView = CustomPDFView()
        context.coordinator.customPDFView = customPDFView
        return customPDFView
    }
    
    func updateNSView(_ nsView: CustomPDFView, context: Context) {
        nsView.updateContent(
            mainPDFData: pdfData,
            overlayPDFData: overlayPDFData,
            overlayOpacity: overlayOpacity
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var customPDFView: CustomPDFView?
    }
}

// Custom PDFView that renders overlay as a layer
class CustomPDFView: NSView {
    private let pdfView: PDFView
    private var overlayView: NSImageView?
    private var overlayPage: PDFPage?
    private var overlayOpacity: Double = 0.75
    private var notificationObservers: [NSObjectProtocol] = []
    
    override init(frame frameRect: NSRect) {
        pdfView = PDFView()
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        pdfView = PDFView()
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        
        // Configure PDF view
        pdfView.autoScales = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)
        
        // Constrain PDF view to fill the custom view
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func updateContent(mainPDFData: Data, overlayPDFData: Data?, overlayOpacity: Double) {
        // Update main PDF
        if let mainDocument = PDFDocument(data: mainPDFData) {
            pdfView.document = mainDocument
        }
        
        // Remove existing overlay view and observers
        overlayView?.removeFromSuperview()
        overlayView = nil
        
        // Remove old notification observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        
        // Add overlay if provided
        if let overlayData = overlayPDFData,
           let overlayDocument = PDFDocument(data: overlayData),
           let page = overlayDocument.page(at: 0) {
            
            print("Creating overlay view for PDF with \(overlayDocument.pageCount) pages")
            
            // Store overlay data
            self.overlayPage = page
            self.overlayOpacity = overlayOpacity
            
            // Create an NSImageView for the overlay
            let imageView = NSImageView()
            imageView.alphaValue = overlayOpacity
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleAxesIndependently // This is important for proper scaling
            
            // Add the overlay view above the PDF view
            addSubview(imageView)
            overlayView = imageView
            
            print("Added overlay view to custom view")
            
            // Update position and content immediately
            updateOverlayPosition()
            
            // Listen for PDF view changes to update overlay position
            let scaleObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewScaleChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.updateOverlayPosition()
            }
            
            let pageObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.updateOverlayPosition()
            }
            
            notificationObservers = [scaleObserver, pageObserver]
        } else {
            print("No overlay data provided or failed to create overlay document")
        }
    }
    
    private func updateOverlayPosition() {
        guard let overlayImageView = overlayView,
              let overlayPDFPage = overlayPage,
              let currentPage = pdfView.currentPage else { 
            print("updateOverlayPosition: missing overlay view, overlay page, or current page")
            return 
        }
        
        // Get the visible rect of the current page in the PDF view
        let pageRect = pdfView.convert(currentPage.bounds(for: .mediaBox), from: currentPage)
        print("updateOverlayPosition: pageRect in view coordinates: \(pageRect)")
        print("updateOverlayPosition: pdfView bounds: \(pdfView.bounds)")
        
        // Convert page rect to custom view coordinates
        let convertedRect = pdfView.convert(pageRect, to: self)
        print("updateOverlayPosition: converted rect: \(convertedRect)")
        
        // Create overlay image at the exact size needed
        let overlayImage = NSImage(size: convertedRect.size)
        overlayImage.lockFocus()
        
        // Fill with debug color
        NSColor.red.withAlphaComponent(0.3).setFill()
        NSRect(origin: .zero, size: convertedRect.size).fill()
        
        // Get the PDF page bounds and calculate scaling
        let pdfBounds = overlayPDFPage.bounds(for: .mediaBox)
        let scaleX = convertedRect.width / pdfBounds.width
        let scaleY = convertedRect.height / pdfBounds.height
        
        // Get the current graphics context and apply scaling
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(x: scaleX, y: scaleY)
            overlayPDFPage.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        
        overlayImage.unlockFocus()
        
        // Update the image view
        overlayImageView.image = overlayImage
        overlayImageView.frame = convertedRect
        
        print("updateOverlayPosition: set overlay frame to \(convertedRect) with image size \(overlayImage.size)")
    }
    
    override func layout() {
        super.layout()
        updateOverlayPosition()
    }
    
    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
