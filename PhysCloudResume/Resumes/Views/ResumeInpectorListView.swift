import SwiftUI

import SwiftUI

struct ResumeInspectorListView: View {
    @Environment(ResStore.self) private var resStore
    @Binding var listSelection: Resume?
    var resumes: [Resume]

    // The persisted string that holds the available styles.
    @AppStorage("availableStyles") private var availableStylesString: String = "Typewriter"
    // The mutable state variable that will drive your UI updates.
    @State private var availableStyles: [String] = []

    var body: some View {
        List {
            ForEach(availableStyles, id: \.self) { style in
                // Filter resumes that match the current style
                let resumesForStyle = resumes.filter { $0.model?.style == style }.sorted { $0.dateCreated > $1.dateCreated }
                if !resumesForStyle.isEmpty {
                    Section(header: Text(style)) {
                        ForEach(resumesForStyle, id: \.id) { resume in
                            ResumeRowView(
                                resume: resume,
                                rowIndex: 0, // Calculate an index if needed
                                isSelected: listSelection == resume,
                                onSelect: {
                                    withAnimation {
                                        listSelection = resume
                                    }
                                },
                                onDelete: {
                                    resStore.deleteRes(resume)
                                }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        // Update availableStyles when the view appears or when the AppStorage string changes.
        .onAppear { updateAvailableStyles() }
        .onChange(of: availableStylesString) {
            updateAvailableStyles()
        }
        .onChange(of: resumes.count) { _ in
            updateAvailableStyles()
        }
    }

    private func updateAvailableStyles() {
        availableStyles = availableStylesString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

// ResInspectorToggleView(res: $selApp.selectedRes)

struct ResumeRowView: View {
    let resume: Resume
    let rowIndex: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(resume.createdDateString)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading) // Changed from `.trailing` to `.leading`
                .lineLimit(1)
                .truncationMode(.tail)

            Text(resume.model!.name)
                .frame(width: 50, alignment: .trailing)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding()
        .padding(.leading, 20)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : (rowIndex % 2 == 0 ? Color.white.opacity(0.8) : Color.gray.opacity(0.1))
        )
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Delete", action: onDelete)
        }
    }
}
