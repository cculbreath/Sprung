import SwiftUI

struct buildToolbar: ToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var selectedTab: TabList
    @Binding var selRes: Resume?
    @State var saveIsHovering: Bool = false
    @Binding var listingButtons: SaveButtons

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
                    resumeToolbarContent(selRes: $selRes)
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
                            saveIsHovering ? .accentColor : .primary).onHover { hovering in
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
            .applyConditionalButtonStyle(editMode: listingButtons.edit)
            .help("Edit job listing")
        }
    }

    @ToolbarContentBuilder
    func emptyToolbarItem() -> some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Spacer()  // Or any empty content
        }
    }
}

struct resumeToolbarContent: ToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var selRes: Resume?
    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if let selectedApp = jobAppStore.selectedApp {
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    print("New resume action")
                }) {
                    Image("new-resume")
                        .font(.system(size: 20, weight: .regular))
                }
                .help("Create new Résumé")
            }
            ToolbarItem(placement: .automatic) {
                Picker(
                    "Load existing résumé draft",
                    selection: $selRes
                ) {
                    Text("None").tag(nil as Resume?) // Handle the nil case explicitly
                    ForEach(selectedApp.resumes, id: \.self) { resume in
                        Text("Created at \(resume.createdDateString)")
                            .tag(Optional(resume)) // Handle the non-nil cases
                            .help("Select a resume to customize")
                    }
                }
                Divider()
            }
            ToolbarItem(placement: .automatic) {
                if let selectedRes = selRes {
                    Button(action: {
                        // Directly assign the result of traverseAndExportNodes to exportD
                        let exportD = TreeNode.traverseAndExportNodes(
                            node: selectedRes.rootNode
                        )

                        // Proceed with JSON serialization
                        do {
                            let jsonData = try JSONSerialization.data(
                                withJSONObject: exportD,
                                options: .prettyPrinted
                            )
                            if let jsonString = String(
                                data: jsonData, encoding: .utf8
                            ) {
                                print(jsonString)
                            }
                        } catch {
                            print("Error serializing JSON: \(error.localizedDescription)")
                        }
                    }) {
                        Image("ai-squiggle")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .help("Generate AI values")
                }
            }
        }
        else {
            ToolbarItem(placement: .automatic) {Text("Somehow, no app :(")}
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
