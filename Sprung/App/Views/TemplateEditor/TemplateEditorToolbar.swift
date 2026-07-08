import SwiftUI

/// In-view control row for the Template Editor. The editor is embedded as the
/// References module's "Templates" tab, and the app uses a custom AppKit
/// NSToolbar (not SwiftUI window toolbars), so these actions render as a plain
/// HStack pinned above the editor content rather than a `.toolbar(id:)` modifier.
struct TemplateEditorToolbar: View {
    @Binding var showSidebar: Bool
    var hasUnsavedChanges: Bool
    var onToggleSidebar: () -> Void
    var onOpenApplicant: () -> Void
    var onOpenExperience: () -> Void
    var onRevert: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleSidebar) {
                Label("Sidebar", systemImage: "sidebar.leading")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(showSidebar ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")

            Divider().frame(height: 16)

            Button(action: onOpenApplicant) {
                Label("Applicant Profile", systemImage: "person.crop.square")
            }
            .buttonStyle(.borderless)
            .help("Open Applicant Profile Editor")

            Button(action: onOpenExperience) {
                Label("Experience Defaults", systemImage: "building.columns")
            }
            .buttonStyle(.borderless)
            .help("Open Experience Editor")

            Spacer()

            Button(action: onRevert) {
                Label("Revert", systemImage: "arrow.uturn.backward.square")
            }
            .buttonStyle(.borderless)
            .disabled(!hasUnsavedChanges)
            .help("Revert all changes to last saved state")

            Button(action: onSave) {
                Label("Save", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasUnsavedChanges)
            .help("Save all changes")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
