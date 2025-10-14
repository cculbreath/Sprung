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
    @Binding var showOverlay: Bool
    let overlayDocument: PDFDocument?
    let overlayPageIndex: Int
    @Binding var overlayOpacity: Double
    let overlayColor: Color
    let isGeneratingPreview: Bool
    let isGeneratingLivePreview: Bool
    let selectedTab: TemplateEditorTab
    let pdfController: PDFPreviewController
    let onReRenderText: () -> Void
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
                if isTextPreviewActive {
                    Button(action: onReRenderText) {
                        Image(systemName: "arrow.trianglehead.2.counterclockwise")
                    }
                    .help("Re-render text preview")
                    .disabled(isGeneratingPreview)
                } else {
                    Button(action: onSaveAndRefresh) {
                        Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                    }
                    .help("Save changes and regenerate PDF preview")
                    .disabled(isGeneratingPreview || !hasUnsavedChanges)

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
                        Image(systemName: "square.arrowtriangle.4.outward")
                    }
                    .help("Fit to page")
                }

                if isTextPreviewActive {
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
