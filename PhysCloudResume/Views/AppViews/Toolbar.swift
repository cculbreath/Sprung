import SwiftUI

struct BuildToolbar: ToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore

    @State var attention: Int = 2

    @Binding var selectedTab: TabList
    @State var saveIsHovering: Bool = false
    @Binding var listingButtons: SaveButtons
    @Binding var letterButtons: CoverLetterButtons
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool

    var body: some ToolbarContent {
        if let selApp = jobAppStore.selectedApp {
            // Use individual toolbar item functions

            @Bindable var selApp = selApp
            // Toolbar content specific to the selected tab
            toolbarContent(for: selectedTab, selRes: $selApp.selectedRes, selApp: selApp)
        }
    }

    @ToolbarContentBuilder
    func toolbarContent(for tab: TabList, selRes: Binding<Resume?>, selApp: JobApp) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            selApp.statusTag
        }
        ToolbarItem(placement: .navigation) {
            twoTierTextToolbar(
                headline: selApp.jobPosition,
                caption: selApp.companyName
            )
        }
        ToolbarItem(placement: .principal) { Spacer() }

        switch tab {
        case .listing:
            if listingButtons.edit {
                ToolbarItem(placement: .primaryAction) { saveButton() }
            } else {
                ToolbarItem(placement: .primaryAction) { toggleEditButton() }
            } case .resume:
            resumeToolbarContent(
                buttons: $resumeButtons,
                selectedResume: selRes
            )
        case .coverLetter:
            if let _ = selApp.selectedCover {
                ToolbarItem(placement: .primaryAction) { CoverLetterToolbar(
                    buttons: $letterButtons,
                    refresh: $refresh
                ) }
            } else {
                ToolbarItem { Text("No Cover Letter Available") } // Handle case where cover letter is nil
            }
        case .submitApp, .none:
            emptyToolbarItem()
        }
    }

    func twoTierTextToolbar(
        headline: String, caption: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment) {
            Text(headline).font(.headline)
            Text(caption).lineLimit(1).font(.caption)
        }
    }

    func saveButton() -> some View {
        Button(action: {
            print("Save button pressed")
            listingButtons.save.toggle()
        }) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(saveIsHovering ? .accentColor : .primary)
                .onHover { hovering in
                    saveIsHovering = hovering
                }
        }
    }

    func toggleEditButton() -> some View {
        return Button(action: {
            listingButtons.edit.toggle()
            print("Edit button toggled")
        }) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(listingButtons.edit ? .accentColor : .primary)
        } /* .applyConditionalButtonStyle(editMode: listingButtons.edit) */
    }

    struct NoHoverButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(Rectangle())
                .background(
                    configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear
                )
        }
    }
}

// extension View {
//  func applyConditionalButtonStyle(editMode: Bool) -> some View {
//    self.buttonStyle(editMode ? BuildToolbar.NoHoverButtonStyle() : PlainButtonStyle())
//  }
// }

func emptyToolbarItem() -> some ToolbarContent {
    ToolbarItem(placement: .automatic) {
        EmptyView()
    }
}

func buildToolbar(
    selectedTab: Binding<TabList>,
    listingButtons: Binding<SaveButtons>,
    letterButtons: Binding<CoverLetterButtons>,
    resumeButtons: Binding<ResumeButtons>,
    refresh: Binding<Bool>
) -> some ToolbarContent {
    BuildToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        letterButtons: letterButtons,
        resumeButtons: resumeButtons,
        refresh: refresh
    )
}
