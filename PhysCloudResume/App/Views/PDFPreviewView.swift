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
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        
        // Main PDF view
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(pdfView)
        
        // Add constraints for main PDF view
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: containerView.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.pdfView = pdfView
        context.coordinator.containerView = containerView
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let pdfView = context.coordinator.pdfView,
              let containerView = context.coordinator.containerView else { return }
        
        // Update main PDF
        if let pdfDocument = PDFDocument(data: pdfData) {
            pdfView.document = pdfDocument
        }
        
        // Remove existing overlay if any
        context.coordinator.overlayView?.removeFromSuperview()
        context.coordinator.overlayView = nil
        
        // Add overlay if requested
        if let overlayData = overlayPDFData,
           let overlayDocument = PDFDocument(data: overlayData) {
            
            let overlayPDFView = PDFView()
            overlayPDFView.autoScales = true
            overlayPDFView.document = overlayDocument
            overlayPDFView.translatesAutoresizingMaskIntoConstraints = false
            overlayPDFView.wantsLayer = true
            overlayPDFView.layer?.opacity = Float(overlayOpacity)
            overlayPDFView.displayMode = .singlePage
            overlayPDFView.backgroundColor = .clear
            
            // Make overlay non-interactive - allow mouse events to pass through
            overlayPDFView.allowedTouchTypes = []
            
            // Sync zoom and page
            overlayPDFView.scaleFactor = pdfView.scaleFactor
            if let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage),
               let overlayPage = overlayDocument.page(at: pageIndex) {
                overlayPDFView.go(to: overlayPage)
            }
            
            containerView.addSubview(overlayPDFView, positioned: .above, relativeTo: pdfView)
            
            // Add constraints for overlay
            NSLayoutConstraint.activate([
                overlayPDFView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                overlayPDFView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                overlayPDFView.topAnchor.constraint(equalTo: containerView.topAnchor),
                overlayPDFView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
            context.coordinator.overlayView = overlayPDFView
            
            // Set up synchronization
            context.coordinator.setupSynchronization()
        } else {
            context.coordinator.teardownSynchronization()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var pdfView: PDFView?
        var overlayView: PDFView?
        var containerView: NSView?
        var notificationObservers: [Any] = []
        
        func setupSynchronization() {
            guard let mainView = pdfView, let _ = overlayView else { return }
            
            // Remove existing observers
            teardownSynchronization()
            
            // Sync zoom changes
            let zoomObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewScaleChanged,
                object: mainView,
                queue: .main
            ) { [weak self] _ in
                guard let self = self,
                      let mainView = self.pdfView,
                      let overlay = self.overlayView else { return }
                overlay.scaleFactor = mainView.scaleFactor
            }
            
            // Sync page changes
            let pageObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: mainView,
                queue: .main
            ) { [weak self] _ in
                guard let self = self,
                      let mainView = self.pdfView,
                      let overlay = self.overlayView,
                      let currentPage = mainView.currentPage,
                      let pageIndex = mainView.document?.index(for: currentPage),
                      let overlayPage = overlay.document?.page(at: pageIndex) else { return }
                overlay.go(to: overlayPage)
            }
            
            notificationObservers = [zoomObserver, pageObserver]
        }
        
        func teardownSynchronization() {
            notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
            notificationObservers.removeAll()
        }
        
        deinit {
            teardownSynchronization()
        }
    }
}