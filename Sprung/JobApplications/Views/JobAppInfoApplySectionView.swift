//
//  JobAppInfoApplySectionView.swift
//  Sprung
//
//
import SwiftUI
struct ApplySection: View {
    @Binding var buttons: SaveButtons
    var body: some View {
        Section {
            Cell(
                leading: "Job Apply Link", trailingKeys: \JobApp.jobApplyLink,
                formTrailingKeys: \JobAppForm.jobApplyLink, isEditing: $buttons.edit
            )
            Cell(
                leading: "Posting URL", trailingKeys: \JobApp.postingURL,
                formTrailingKeys: \JobAppForm.postingURL, isEditing: $buttons.edit
            )
        }
        .insetGroupedStyle(header: Text("Apply"))
    }
}
