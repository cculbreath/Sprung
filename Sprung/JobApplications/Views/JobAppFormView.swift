//
//  JobAppFormView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//

import SwiftUI

// func binding(for optionalString: Binding<String?>, default value: String = "")
// -> Binding<String>
// {
//    return Binding<String>(
//        get: { optionalString.wrappedValue ?? value },
//        set: { newValue in
//            optionalString.wrappedValue = newValue.isEmpty ? nil : newValue
//        }
//    )
// }

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
