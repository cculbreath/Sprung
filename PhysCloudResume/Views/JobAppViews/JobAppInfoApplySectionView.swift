import SwiftUI

struct ApplySection: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Binding var buttons: SaveButtons

  var body: some View {
    Section {
      Cell(
        leading: "Job Apply Link", trailingKeys: \JobApp.job_apply_link,
        formTrailingKeys: \JobAppForm.job_apply_link, isEditing: $buttons.edit)
    }
    .insetGroupedStyle(header: Text("Apply"))
  }
}
