import SwiftUI

struct TemplateEditorToolbar: CustomizableToolbarContent {
    @Binding var showSidebar: Bool
    @Binding var showInspector: Bool
    var hasUnsavedChanges: Bool
    var canRevert: Bool
    var onRefresh: () -> Void
    var onRevert: () -> Void
    var onClose: () -> Void
    var onToggleInspector: () -> Void
    var onToggleSidebar: () -> Void
    var onOpenApplicant: () -> Void

    var body: some CustomizableToolbarContent {
        navigationItems
        applicantItem
        actionItems
        inspectorItem
        statusItem
        closeItem
    }

    private var navigationItems: some CustomizableToolbarContent {
        ToolbarItem(id: "toggleSidebar", placement: .navigation, showsByDefault: true) {
            Button(action: onToggleSidebar) {
                Label("Sidebar", systemImage: showSidebar ? "sidebar.leading" : "sidebar.leading")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(showSidebar ? Color.accentColor : Color.secondary)
            }
            .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
        }
    }

    private var inspectorItem: some CustomizableToolbarContent {
        ToolbarItem(id: "toggleInspector", placement: .automatic, showsByDefault: true) {
            Button(action: onToggleInspector) {
                Label("Preview", systemImage: showInspector ? "sidebar.trailing" : "sidebar.trailing")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(showInspector ? Color.accentColor : Color.secondary)
            }
            .help(showInspector ? "Hide Preview" : "Show Preview")
        }
    }

    private var applicantItem: some CustomizableToolbarContent {
        ToolbarItem(id: "applicantProfile", placement: .automatic, showsByDefault: true) {
            Button(action: onOpenApplicant) {
                Label("Applicant Profile", systemImage: "person.crop.square")
            }
            .help("Open Applicant Profile Editor")
        }
    }

    private var actionItems: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "refresh", placement: .primaryAction, showsByDefault: true) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Save changes and regenerate preview")
            }

            ToolbarItem(id: "revert", placement: .primaryAction, showsByDefault: true) {
                Button(action: onRevert) {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canRevert)
                .help("Discard unsaved edits")
            }
        }
    }

    private var closeItem: some CustomizableToolbarContent {
        ToolbarItem(id: "close", placement: .cancellationAction, showsByDefault: true) {
            Button(action: onClose) {
                Label("Close", systemImage: "xmark.circle")
            }
            .help("Save changes and close editor")
        }
    }

    private var statusItem: some CustomizableToolbarContent {
        ToolbarItem(id: "unsavedStatus", placement: .status, showsByDefault: true) {
            if hasUnsavedChanges {
                Label("Unsaved", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
            }
        }
    }
}
