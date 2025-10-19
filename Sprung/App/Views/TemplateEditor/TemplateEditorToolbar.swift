import SwiftUI

struct TemplateEditorToolbar: CustomizableToolbarContent {
    @Binding var showSidebar: Bool
    var hasUnsavedChanges: Bool
    var onToggleSidebar: () -> Void
    var onOpenApplicant: () -> Void
    var onOpenExperience: () -> Void
    var onCloseWithoutSaving: () -> Void
    var onRevert: () -> Void
    var onSaveAndClose: () -> Void

    var body: some CustomizableToolbarContent {
        navigationItems
        applicantItem
        experienceItem
        closeWithoutSavingItem
        revertItem
        saveItem
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

    private var applicantItem: some CustomizableToolbarContent {
        ToolbarItem(id: "applicantProfile", placement: .navigation, showsByDefault: true) {
            Button(action: onOpenApplicant) {
                Label("Applicant Profile", systemImage: "person.crop.square")
            }
            .help("Open Applicant Profile Editor")
        }
    }

    private var experienceItem: some CustomizableToolbarContent {
        ToolbarItem(id: "experienceEditor", placement: .navigation, showsByDefault: true) {
            Button(action: onOpenExperience) {
                Label("Experience Defaults", systemImage: "briefcase")
            }
            .help("Open Experience Editor")
        }
    }

    private var closeWithoutSavingItem: some CustomizableToolbarContent {
        ToolbarItem(id: "closeWithoutSaving", placement: .cancellationAction, showsByDefault: true) {
            Button(action: onCloseWithoutSaving) {
                Label("Close Without Saving", systemImage: "x.circle")
            }
            .help("Close editor and discard unsaved edits")
        }
    }

    private var revertItem: some CustomizableToolbarContent {
        ToolbarItem(id: "revertAll", placement: .primaryAction, showsByDefault: true) {
            Button(action: onRevert) {
                Label("Revert", systemImage: "arrow.uturn.backward.square")
            }
            .disabled(!hasUnsavedChanges)
            .help("Revert all changes to last saved state")
        }
    }

    private var saveItem: some CustomizableToolbarContent {
        ToolbarItem(id: "saveAndClose", placement: .confirmationAction, showsByDefault: true) {
            Button(action: onSaveAndClose) {
                Label("Save and Close", systemImage: "checkmark.circle")
            }
            .disabled(!hasUnsavedChanges)
            .help("Save all changes and close editor")
        }
    }
}
