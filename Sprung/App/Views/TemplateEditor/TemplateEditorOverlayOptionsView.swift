//
//  TemplateEditorOverlayOptionsView.swift
//  Sprung
//
import SwiftUI
struct TemplateEditorOverlayOptionsView: View {
    let overlayFilename: String?
    let overlayPageCount: Int
    @Binding var overlayPageSelection: Int
    @Binding var overlayColorSelection: Color
    let canClearOverlay: Bool
    let canSaveOverlay: Bool
    let onChooseOverlay: () -> Void
    let onClearOverlay: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Overlay Options")
                .font(.title3)
                .fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 8) {
                Text(overlayFilename ?? "No overlay selected")
                    .font(.subheadline)
                HStack {
                    Button("Choose…", action: onChooseOverlay)
                    if canClearOverlay {
                        Button("Clear", role: .destructive, action: onClearOverlay)
                    }
                }
            }
            if overlayPageCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overlay Page")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper(value: $overlayPageSelection, in: 0...max(overlayPageCount - 1, 0)) {
                        Text("Page \(overlayPageSelection + 1) of \(overlayPageCount)")
                    }
                }
            }
            ColorPicker("Overlay Color", selection: $overlayColorSelection, supportsOpacity: true)
            Spacer()
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Save", action: onSave)
                    .disabled(!canSaveOverlay)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
        .onDisappear(perform: onDismiss)
    }
}
