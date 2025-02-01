import SwiftUI

struct ResumeInspectorListView: View {
    @Environment(ResStore.self) private var resStore
    @Binding var listSelection: Resume?
    @Binding var resumes: [Resume]

    // Precompute the sorted resumes
    private var sortedResumes: [Resume] {
        resumes.sorted { $0.dateCreated > $1.dateCreated }
    }

    var body: some View {
        VStack {
            // Header
            HStack {
                Text("Date Created")
                    .fontWeight(.bold)
                    .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading) // Changed from `.trailing` to `.leading`

                Text("Model")
                    .fontWeight(.bold)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.top, 5)

            Divider()

            // List of Resumes
            ScrollView {
                VStack(spacing: 0) {
                    // Enumerate to get index and resume
                    ForEach(Array(sortedResumes.enumerated()), id: \.element.id) { index, resume in
                        ResumeRowView(
                            resume: resume,
                            rowIndex: index,
                            isSelected: self.listSelection == resume,
                            onSelect: {
                                withAnimation {
                                    self.listSelection = resume
                                }
                            },
                            onDelete: {
                                resStore.deleteRes(resume)
                                if let index = resumes.firstIndex(of: resume) {
                                    resumes.remove(at: index)
                                }
                            }
                        )
                    }
                }
            }
        }
        .frame(minWidth: 200, minHeight: 100)
    }

    private func removeSelectedResume() {
        if let selected = listSelection, let index = resumes.firstIndex(of: selected) {
            resStore.deleteRes(selected)
            resumes.remove(at: index)
            listSelection = resumes.first
        }
    }
}

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
