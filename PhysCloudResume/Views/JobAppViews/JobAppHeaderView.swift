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
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Job Application", systemImage: "trash")
                        .padding(5)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
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
        }
        .padding(.vertical, 0)
    }
}
