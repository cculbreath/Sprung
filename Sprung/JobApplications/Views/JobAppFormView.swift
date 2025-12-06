//
//  JobAppFormView.swift
//  Sprung
//
//
import SwiftUI
struct JobAppPostingDetailsSection: View {
    @Binding var buttons: SaveButtons
    var body: some View {
        Section {
            Cell(
                leading: "Job Position", trailingKeys: \JobApp.jobPosition,
                formTrailingKeys: \JobAppForm.jobPosition, isEditing: $buttons.edit
            )
            Cell(
                leading: "Job Location", trailingKeys: \JobApp.jobLocation,
                formTrailingKeys: \JobAppForm.jobLocation, isEditing: $buttons.edit
            )
            Cell(
                leading: "Company Name", trailingKeys: \JobApp.companyName,
                formTrailingKeys: \JobAppForm.companyName, isEditing: $buttons.edit
            )
            Cell(
                leading: "Company LinkedIn ID", trailingKeys: \JobApp.companyLinkedinId,
                formTrailingKeys: \JobAppForm.companyLinkedinId, isEditing: $buttons.edit
            )
            Cell(
                leading: "Posting URL", trailingKeys: \JobApp.postingURL,
                formTrailingKeys: \JobAppForm.postingURL, isEditing: $buttons.edit
            )
            Cell(
                leading: "Job Posting Time", trailingKeys: \JobApp.jobPostingTime,
                formTrailingKeys: \JobAppForm.jobPostingTime, isEditing: $buttons.edit
            )
        }
        .insetGroupedStyle(header: Text("Posting Details"))
    }
}
