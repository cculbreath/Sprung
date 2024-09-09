import SwiftUI

//func binding(for optionalString: Binding<String?>, default value: String = "")
//-> Binding<String>
//{
//    return Binding<String>(
//        get: { optionalString.wrappedValue ?? value },
//        set: { newValue in
//            optionalString.wrappedValue = newValue.isEmpty ? nil : newValue
//        }
//    )
//}

struct JobAppPostingDetailsSection: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore  // Explicit type
  @Binding var buttons: SaveButtons

  var body: some View {
    Section {
      Cell(
        leading: "Job Position", trailingKeys: \JobApp.job_position,
        formTrailingKeys: \JobAppForm.job_position, isEditing: $buttons.edit)
      Cell(
        leading: "Job Location", trailingKeys: \JobApp.job_location,
        formTrailingKeys: \JobAppForm.job_location, isEditing: $buttons.edit)
      Cell(
        leading: "Company Name", trailingKeys: \JobApp.company_name,
        formTrailingKeys: \JobAppForm.company_name, isEditing: $buttons.edit)
      Cell(
        leading: "Company LinkedIn ID", trailingKeys: \JobApp.company_linkedin_id,
        formTrailingKeys: \JobAppForm.company_linkedin_id, isEditing: $buttons.edit)
      Cell(
        leading: "Job Posting Time", trailingKeys: \JobApp.job_posting_time,
        formTrailingKeys: \JobAppForm.job_posting_time, isEditing: $buttons.edit)
    }
    .insetGroupedStyle(header: Text("Posting Details"))
  }
}
