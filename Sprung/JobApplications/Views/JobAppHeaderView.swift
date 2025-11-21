//
//  JobAppHeaderView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//
import SwiftData
import SwiftUI
struct HeaderView: View {
    @Binding var showingDeleteConfirmation: Bool
    @Binding var buttons: SaveButtons
    @Binding var tab: TabList
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore // Explicit type
    var body: some View {
        HStack {
            Spacer()

            if buttons.edit {
                // Edit mode: Show Save, Cancel, and Delete buttons
                HStack(spacing: 12) {
                    Button {
                        buttons.save = true
                    } label: {
                        Label("Save", systemImage: "checkmark.circle")
                            .padding(5)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Save changes")

                    Button {
                        buttons.cancel = true
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .padding(5)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel editing")

                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .padding(5)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete job application")
                    .confirmationDialog(
                        "Are you sure you want to delete this job application?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            buttons.edit = false
                            jobAppStore.deleteSelected()
                            tab = TabList.none
                        }
                        Button("Cancel", role: .cancel) {
                            // Just dismiss the dialog
                        }
                    }
                }
            } else {
                // View mode: Show Edit button
                Button {
                    buttons.edit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .padding(5)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Edit job application")
            }
        }
        .padding(.vertical, 0)
    }
}
