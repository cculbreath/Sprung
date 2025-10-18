//
//  ResumeInspectorListView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//

import AppKit
import SwiftUI

struct ResumeInspectorListView: View {
    @Environment(ResStore.self) private var resStore
    @Binding var listSelection: Resume?
    var resumes: [Resume]

    var body: some View {
        let sortedResumes = resumes.sorted { $0.dateCreated > $1.dateCreated }

        if sortedResumes.isEmpty {
            Text("No resumes yet. Create one below to get started.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color.white)
                .cornerRadius(12)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sortedResumes, id: \.id) { resume in
                    ResumeRowView(
                        resume: resume,
                        isSelected: listSelection == resume,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.12)) {
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
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.05),
                value: resumes.map(\.id)
            )
        }
    }
}

struct ResumeRowView: View {
    let resume: Resume
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resume.createdDateString)
                        .font(.subheadline)
                        .foregroundColor(isSelected ? Color.white : Color.secondary)
                        .lineLimit(1)

                    Text(resume.template?.name ?? resume.template?.slug.capitalized ?? "-")
                        .font(.footnote)
                        .foregroundColor(isSelected ? Color.white : Color.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2),
                                lineWidth: isSelected ? 1.1 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Duplicate", action: onDuplicate)
            Button("Delete", action: onDelete)
        }
    }
}
