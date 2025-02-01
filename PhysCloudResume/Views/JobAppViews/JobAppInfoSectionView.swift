import SwiftUI

struct JobAppInformationSection: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var isHovered: Bool = false
    @Binding var buttons: SaveButtons

    var body: some View {
        Section {
            Cell(
                leading: "Seniority Level", trailingKeys: \JobApp.seniority_level,
                formTrailingKeys: \JobAppForm.seniority_level, isEditing: $buttons.edit
            )
            Cell(
                leading: "Employment Type", trailingKeys: \JobApp.employment_type,
                formTrailingKeys: \JobAppForm.employment_type, isEditing: $buttons.edit
            )
            Cell(
                leading: "Job Function", trailingKeys: \JobApp.job_function,
                formTrailingKeys: \JobAppForm.job_function, isEditing: $buttons.edit
            )
            Cell(
                leading: "Industries", trailingKeys: \JobApp.industries,
                formTrailingKeys: \JobAppForm.industries, isEditing: $buttons.edit
            )
        }
        .insetGroupedStyle(header: Text("Job Information"))
    }
}
