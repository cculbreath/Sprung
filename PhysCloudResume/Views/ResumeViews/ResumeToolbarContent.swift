import SwiftUI

struct buildToolbar: ToolbarContent {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResStore.self) private var resStore: ResStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore

  @Binding var selectedTab: TabList
  @Binding var selRes: Resume?
  @State var saveIsHovering: Bool = false
  @Binding var listingButtons: SaveButtons
  @State var attention: Int = 2

  @ToolbarContentBuilder
  var body: some ToolbarContent {
    if let selApp = jobAppStore.selectedApp {
      ToolbarItem(placement: .navigation) {
        selApp.statusTag
      }

      twoTierTextToolbar(
        headline: selApp.job_position,
        caption: selApp.company_name
      )

      switch selectedTab {
        case .listing:
          listingToolbarItem()
        case .resume:
          resumeToolbarContent(selRes: $selRes)  // This stays the same
        case .coverLetter, .submitApp:
          emptyToolbarItem()
        case .none:
          emptyToolbarItem()
      }
    }
  }

  @ToolbarContentBuilder
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

  @ToolbarContentBuilder
  func listingToolbarItem() -> some ToolbarContent {
    ToolbarItem(placement: .automatic) {
      Spacer()
    }
    ToolbarItemGroup(placement: .primaryAction) {
      if listingButtons.edit {
        Button(action: {
          listingButtons.save.toggle()
          print("Save")
        }) {
          Image(systemName: "checkmark.circle")
            .font(.system(size: 40, weight: .light))
            .foregroundColor(
              saveIsHovering ? .accentColor : .primary
            ).onHover { hovering in
              saveIsHovering = hovering
            }
        }
      }

      Button(action: {
        print("Toggle")
        if !listingButtons.edit {
          listingButtons.edit = true
        } else {
          listingButtons.edit = false
        }

        print(
          "Listing is now \(listingButtons.edit ? "true" : "false")")
      }) {
        Image(systemName: "pencil.and.list.clipboard")
          .font(.system(size: 20, weight: .light))
          .foregroundColor(
            listingButtons.edit ? .accentColor : .primary)
      }
      .applyConditionalButtonStyle(editMode: listingButtons.edit)  // Apply the button style correctly
      .help("Edit job listing")
    }
  }

  @ToolbarContentBuilder
  func resumeToolbarContent(selRes: Binding<Resume?>) -> some ToolbarContent {
    if let selectedApp = jobAppStore.selectedApp {
      // Ensure selRes has a value if it is nil
      let unwrappedSelRes = Binding<Resume?>(
        get: { selRes.wrappedValue ?? selectedApp.resumes.first },  // Return the first resume or nil
        set: { selRes.wrappedValue = $0 }  // Update the binding
      )
      emptyToolbarItem()
      // ToolbarItem: Picker for resume selection
      ToolbarItem(placement: .automatic) {
        Picker(
          "Load existing résumé draft",
          selection: unwrappedSelRes
        ) {
          Text("None").tag(nil as Resume?)
          ForEach(selectedApp.resumes, id: \.self) { resume in
            Text("Created at \(resume.createdDateString)")
              .tag(Optional(resume))
              .help("Select a resume to customize")
          }
        }
        .frame(maxHeight: .infinity, alignment: .trailing)
      }

      // ToolbarItem: Custom Stepper for attention control
      ToolbarItem(placement: .automatic) {
        CustomStepper(value: $attention, range: 0...4)
          .padding(.vertical, 0)
          .overlay {
            Text("Attention Grab")
              .font(.caption2)
              .padding(.vertical, 0)
              .lineLimit(1)
              .minimumScaleFactor(0.9)
              .fontWeight(.light)
              .offset(y: 18)
          }
          .offset(y: -1)
          .padding(.trailing, 2)
          .padding(.leading, 6)
      }

      // ToolbarItem: AiFunctionView or fallback text
      ToolbarItem(placement: .automatic) {
        if selRes.wrappedValue?.rootNode != nil {
          AiFunctionView(res: unwrappedSelRes, attn: $attention)
        } else {
          Text(":(")
        }
      }
    } else {
      // Optional: Provide default toolbar content in case there's no selectedApp
      ToolbarItem(placement: .automatic) {
        Text("No job application selected")
      }
    }
  }

  @ToolbarContentBuilder
  func emptyToolbarItem() -> some ToolbarContent {
    ToolbarItem(placement: .automatic) {
      Spacer()  // Or any empty content
    }
  }
}

struct NoHoverButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())  // Ensure the entire button area is clickable
      .background(
        configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
  }
}

extension View {
  func applyConditionalButtonStyle(editMode: Bool) -> some View {
    if editMode {
      return AnyView(self.buttonStyle(NoHoverButtonStyle()))
    } else {
      return AnyView(self.buttonStyle(PlainButtonStyle()))
    }
  }
}
