import SwiftUI

struct BuildToolbar: ToolbarContent {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResStore.self) private var resStore: ResStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore
  @State var attention: Int = 2

  @Binding var selectedTab: TabList
  @Binding var selRes: Resume?
  @State var saveIsHovering: Bool = false
  @Binding var listingButtons: SaveButtons
  @Binding var letterButtons: CoverLetterButtons

  var body: some ToolbarContent {
    if let selApp = jobAppStore.selectedApp {
      // Use individual toolbar item functions
      ToolbarItem(placement: .navigation) {
        selApp.statusTag
      }

      twoTierTextToolbar(
        headline: selApp.job_position,
        caption: selApp.company_name
      )
      
      // Always show resumePicker regardless of selectedTab
      if selRes != nil, let selectedApp = selRes?.jobApp {
        resumePicker(selectedApp: selectedApp)
      }

      // Toolbar content specific to the selected tab
      toolbarContent(for: selectedTab, selRes: $selRes)
    }
  }

  @ToolbarContentBuilder
  func toolbarContent(for tab: TabList, selRes: Binding<Resume?>) -> some ToolbarContent {
    switch tab {
      case .listing:
        listingToolbarItem()
      case .resume:
        resumeToolbarContent(selRes: selRes, selectedApp: jobAppStore.selectedApp, attention: $attention)
      case .coverLetter:
        CoverLetterToolbar(buttons: $letterButtons)
      case .submitApp, .none:
        emptyToolbarItem()
    }
  }

  func twoTierTextToolbar(
    headline: String, caption: String,
    alignment: HorizontalAlignment = .leading
  ) -> some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      VStack(alignment: alignment) {
        Text(headline).font(.headline)
        Text(caption).lineLimit(1).font(.caption)
      }
    }
  }

  // Define saveButton to return a ToolbarItem
  // Define saveButton to return a ToolbarItem with flexible content (some View)
  func saveButton() -> ToolbarItem<Void, some View> {
    ToolbarItem(placement: .primaryAction) {
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
      .help("Save changes")
    }
  }

  // Define toggleEditButton to return a ToolbarItem with flexible content (some View)
  func toggleEditButton() -> ToolbarItem<Void, some View> {
    ToolbarItem(placement: .primaryAction) {
      Button(action: {
        listingButtons.edit.toggle()
        print("Edit button toggled")
      }) {
        Image(systemName: "pencil.and.list.clipboard")
          .font(.system(size: 20, weight: .light))
          .foregroundColor(listingButtons.edit ? .accentColor : .primary)
      }
      .applyConditionalButtonStyle(editMode: listingButtons.edit)
      .help("Edit job listing")
    }
  }

  // Update listingToolbarItem to return multiple ToolbarItems
  @ToolbarContentBuilder
  func listingToolbarItem() -> some ToolbarContent {
    if listingButtons.edit {
      saveButton()
    }
    toggleEditButton()
  }
  @ToolbarContentBuilder
  func resumePicker(selectedApp: JobApp) -> some ToolbarContent {
    // Insert a toolbar group to control the alignment with a Spacer
    ToolbarItemGroup(placement: .automatic) {
      Spacer()  // Acts as a flexible spacer to push the picker to the right

      // Resume picker
      Picker(
        "Load existing résumé draft",
        selection: $selRes
      ) {
        Text("None").tag(nil as Resume?)
        ForEach(selectedApp.resumes, id: \.self) { resume in
          Text("Created at \(resume.createdDateString)")
            .tag(Optional(resume) as Resume?)
            .help("Select a resume to customize")
        }
      }
      .frame(maxHeight: .infinity, alignment: .trailing)
    }
  }
  struct NoHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .contentShape(Rectangle())  // Ensure the entire button area is clickable
        .background(
          configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear
        )
    }
  }
}

extension View {
  func applyConditionalButtonStyle(editMode: Bool) -> some View {
    if editMode {
      return AnyView(self.buttonStyle(BuildToolbar.NoHoverButtonStyle()))
    } else {
      return AnyView(self.buttonStyle(PlainButtonStyle()))
    }
  }
}

func emptyToolbarItem() -> some ToolbarContent {
  ToolbarItem(placement: .automatic) {
    Spacer()  // Or any empty content
  }
}

func buildToolbar(
  selectedTab: Binding<TabList>,
  selRes: Binding<Resume?>,
  listingButtons: Binding<SaveButtons>,
  letterButtons: Binding<CoverLetterButtons>
) -> some ToolbarContent {
  BuildToolbar(
    selectedTab: selectedTab,
    selRes: selRes,
    listingButtons: listingButtons,
    letterButtons: letterButtons
  )
}
