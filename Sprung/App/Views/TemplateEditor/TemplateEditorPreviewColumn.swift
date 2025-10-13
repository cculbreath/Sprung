//
//  TemplateEditorPreviewColumn.swift
//  Sprung
//

import PDFKit
import SwiftUI

struct TemplateEditorPreviewColumn: View {
    let previewPDFData: Data?
    let textPreview: String?
    @Binding var showOverlay: Bool
    let overlayDocument: PDFDocument?
    let overlayPageIndex: Int
    @Binding var overlayOpacity: Double
    let overlayColor: Color
    let isGeneratingPreview: Bool
    let isGeneratingLivePreview: Bool
    let selectedTab: TemplateEditorTab
    let pdfController: PDFPreviewController
    let onRefresh: () -> Void
    let onPrepareOverlayOptions: () -> Void

    private var isTextPreviewActive: Bool {
        selectedTab == .txtTemplate
    }

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
        if isTextPreviewActive {
            textPreviewView()
        } else if let pdfData = previewPDFData {
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
            previewUnavailableMessage("PDF preview will render after template defaults are generated.")
        }
    }

    @ViewBuilder
    private func previewToolbar() -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isTextPreviewActive ? "Text Preview" : "PDF Preview")
                        .font(.headline)
                    Text("(Template Seed)")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                if isGeneratingLivePreview || isGeneratingPreview {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isTextPreviewActive ? "Rendered from template default values." : "Generated from template seed data.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .padding(.top, 2)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.triangle.head.2.clockwise")
                }
                .help(isTextPreviewActive ? "Refresh Text Preview" : "Refresh PDF Preview")
                .disabled(isGeneratingPreview)

                if !isTextPreviewActive {
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
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func previewFooter() -> some View {
        if isTextPreviewActive {
            HStack { Spacer() }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
        } else {
            HStack(spacing: 12) {
                if overlayDocument != nil {
                    HStack(spacing: 8) {
                        Text("Overlay Opacity")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Slider(value: $overlayOpacity, in: 0...1)
                            .frame(width: 140)
                    }
                }

                Button(action: onPrepareOverlayOptions) {
                    Label("Choose Overlay…", systemImage: "square.on.square")
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingPreview)

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

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func textPreviewView() -> some View {
        if let textPreview, !textPreview.isEmpty {
            ScrollView {
                Text(textPreview)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Color(NSColor.textBackgroundColor))
        } else {
            previewUnavailableMessage("Text preview will render after template defaults are generated.")
        }
    }

    private func previewUnavailableMessage(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Preview will appear here")
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
