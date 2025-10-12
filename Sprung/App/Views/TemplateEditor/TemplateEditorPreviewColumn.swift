//
//  TemplateEditorPreviewColumn.swift
//  Sprung
//

import PDFKit
import SwiftUI

struct TemplateEditorPreviewColumn: View {
    let previewPDFData: Data?
    @Binding var showOverlay: Bool
    let overlayDocument: PDFDocument?
    let overlayPageIndex: Int
    @Binding var overlayOpacity: Double
    let overlayColor: Color
    let isGeneratingPreview: Bool
    let isGeneratingLivePreview: Bool
    let selectedTab: TemplateEditorTab
    let isEditingCurrentTemplate: Bool
    let hasSelectedResume: Bool
    let pdfController: PDFPreviewController
    let onRefresh: () -> Void
    let onPrepareOverlayOptions: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            previewToolbar()
            Divider()
            previewContent()
            Divider()
            previewFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func previewContent() -> some View {
        if let pdfData = previewPDFData {
            PDFPreviewView(
                pdfData: pdfData,
                overlayDocument: showOverlay ? overlayDocument : nil,
                overlayPageIndex: overlayPageIndex,
                overlayOpacity: overlayOpacity,
                overlayColor: overlayColor.toNSColor(),
                controller: pdfController
            )
            .background(Color(NSColor.textBackgroundColor))
        } else {
            previewUnavailableMessage(
                hasSelectedResume
                    ? "Export the resume in the main window to see PDF output."
                    : "Select a resume in the main window to enable preview."
            )
        }
    }

    @ViewBuilder
    private func previewToolbar() -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Preview")
                        .font(.headline)
                    Text(isEditingCurrentTemplate ? "(Live)" : "(Current Resume)")
                        .font(.caption)
                        .foregroundStyle(isEditingCurrentTemplate ? Color.orange : Color.secondary)
                }
                if isGeneratingLivePreview || isGeneratingPreview {
                    ProgressView()
                        .controlSize(.small)
                }
                if selectedTab != .pdfTemplate {
                    Text("Preview always shows the PDF template; other tab edits save automatically.")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    pdfController.goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!pdfController.canGoToPreviousPage)

                Button {
                    pdfController.goToNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!pdfController.canGoToNextPage)

                Divider()
                    .frame(height: 16)

                Button {
                    pdfController.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }

                Button {
                    pdfController.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }

                Button {
                    pdfController.resetZoom()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit to page")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func previewFooter() -> some View {
        HStack(spacing: 12) {
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTab != .pdfTemplate || isGeneratingPreview || !hasSelectedResume)

            Spacer()

            if overlayDocument != nil {
                HStack(spacing: 8) {
                    Text("Overlay Opacity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $overlayOpacity, in: 0...1)
                        .frame(width: 140)
                }
            }

            Button(action: onPrepareOverlayOptions) {
                Label("Choose Overlay…", systemImage: "square.on.square")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTab != .pdfTemplate || isGeneratingPreview)

            if overlayDocument != nil {
                HStack(spacing: 12) {
                    Toggle("Overlay", isOn: $showOverlay)
                        .toggleStyle(.switch)
                    Slider(value: $overlayOpacity, in: 0...1)
                        .frame(width: 140)
                }
            } else {
                Toggle("Overlay", isOn: $showOverlay)
                    .toggleStyle(.switch)
                    .disabled(true)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func previewUnavailableMessage(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("PDF preview will appear here")
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            pdfController.updatePagingState()
        }
    }
}
