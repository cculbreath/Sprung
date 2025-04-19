import SwiftUI

struct ApplySection: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var buttons: SaveButtons

    var body: some View {
        Section {
            Cell(
                leading: "Job Apply Link", trailingKeys: \JobApp.jobApplyLink,
                formTrailingKeys: \JobAppForm.jobApplyLink, isEditing: $buttons.edit
            )
        }
        .insetGroupedStyle(header: Text("Apply"))
    }
}
