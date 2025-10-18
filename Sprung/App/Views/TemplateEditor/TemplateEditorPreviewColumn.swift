//
//  TemplateEditorPreviewColumn.swift
//  Sprung
//

import AppKit
import PDFKit
import SwiftUI

struct TemplateEditorPreviewColumn: View {
    let previewPDFData: Data?
    let textPreview: String?
    let previewError: String?
    @Binding var showOverlay: Bool
    let overlayDocument: PDFDocument?
    let overlayPageIndex: Int
    @Binding var overlayOpacity: Double
    let overlayColor: Color
    let isGeneratingPreview: Bool
    let isGeneratingLivePreview: Bool
    let selectedTab: TemplateEditorTab
    let pdfController: PDFPreviewController
    let onForceRefresh: () -> Void
    let onSaveAndRefresh: () -> Void
    let hasUnsavedChanges: Bool
    let onPrepareOverlayOptions: () -> Void
    @State private var textPreviewFontSize: CGFloat = TextPreviewAppearance.defaultFontSize

    private var isTextPreviewActive: Bool {
        selectedTab == .txtTemplate
    }

    private var textPreviewFont: Font {
        .system(size: textPreviewFontSize, weight: .regular, design: .monospaced)
    }

    private var textPreviewFontLabel: String {
        "\(Int(textPreviewFontSize)) pt"
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
        ZStack {
            Color(NSColor.textBackgroundColor)
            if let error = previewError {
                previewErrorView(error)
            } else if isTextPreviewActive {
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
            } else {
                previewUnavailableMessage("PDF preview will render after template defaults are generated.")
            }
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
                Text(isTextPreviewActive ? "Rendered from template default values." : "Generated from template seed data.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .padding(.top, 2)
            }

            Spacer()

            HStack(spacing: 8) {
                let isAnimatingRefresh = isGeneratingPreview || isGeneratingLivePreview
                let refreshHelp = hasUnsavedChanges ? "Save changes and regenerate preview" : "Regenerate preview"

                TemplateRefreshButton(
                    hasUnsavedChanges: hasUnsavedChanges,
                    isAnimating: isAnimatingRefresh,
                    isEnabled: !isAnimatingRefresh,
                    help: isAnimatingRefresh ? "Generating preview…" : refreshHelp,
                    action: {
                    if hasUnsavedChanges {
                        onSaveAndRefresh()
                    } else {
                        onForceRefresh()
                    }
                    }
                )

                if !isTextPreviewActive {
                    Button {
                        pdfController.goToPreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!pdfController.canGoToPreviousPage)
                    .help("Previous page")

                    Button {
                        pdfController.goToNextPage()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!pdfController.canGoToNextPage)
                    .help("Next page")

                    Divider()
                        .frame(height: 16)

                    Button {
                        pdfController.zoomOut()
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Zoom out")

                    Button {
                        pdfController.zoomIn()
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Zoom in")

                    Button {
                        pdfController.resetZoom()
                    } label: {
                        Image(systemName: "square.arrowtriangle.4.outward")
                    }
                    .help("Fit to page")
                } else {
                    Divider()
                        .frame(height: 16)
                    Button {
                        decreaseFontSize()
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .help("Decrease font size")
                    .disabled(textPreviewFontSize <= TextPreviewAppearance.minFontSize)

                    Text(textPreviewFontLabel)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .frame(minWidth: 44, alignment: .center)

                    Button {
                        increaseFontSize()
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .help("Increase font size")
                    .disabled(textPreviewFontSize >= TextPreviewAppearance.maxFontSize)
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
        if previewError != nil {
            HStack { Spacer() }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
        } else if isTextPreviewActive {
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
                .help("Select or manage overlay PDF")

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
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(textPreview)
                        .font(textPreviewFont)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    Spacer(minLength: 0)
                }
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
    
    private func previewErrorView(_ message: String) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text("Template preview failed")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            pdfController.updatePagingState()
        }
    }

    private func increaseFontSize() {
        textPreviewFontSize = min(TextPreviewAppearance.maxFontSize, textPreviewFontSize + 1)
    }

    private func decreaseFontSize() {
        textPreviewFontSize = max(TextPreviewAppearance.minFontSize, textPreviewFontSize - 1)
    }
}

private enum TextPreviewAppearance {
    static let minFontSize: CGFloat = 10
    static let defaultFontSize: CGFloat = 13
    static let maxFontSize: CGFloat = 18
}
