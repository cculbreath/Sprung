//
//  ResumeInpectorListView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//

import SwiftUI

import SwiftUI

struct ResumeInspectorListView: View {
    @Environment(ResStore.self) private var resStore
    @Binding var listSelection: Resume?
    var resumes: [Resume]

    var body: some View {
        let sortedResumes = resumes.sorted { $0.dateCreated > $1.dateCreated }
        List(sortedResumes, id: \.id) { resume in
            ResumeRowView(
                resume: resume,
                isSelected: listSelection == resume,
                onSelect: {
                    withAnimation {
                        listSelection = resume
                    }
                },
                onDelete: {
                    resStore.deleteRes(resume)
                },
                onDuplicate: {
                    resStore.duplicate(resume)
                }
            )
        }
        .listStyle(.plain)
    }
}

// ResInspectorToggleView(res: $selApp.selectedRes)

struct ResumeRowView: View {
    let resume: Resume
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        HStack {
            Text(resume.createdDateString)
                .frame(minWidth: 140, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(resume.template?.name ?? resume.template?.slug.capitalized ?? "-")
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Duplicate", action: onDuplicate)
            Button("Delete", action: onDelete)
        }
    }
}
