//
//  JobAppInfoSectionView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import SwiftUI

struct JobAppInformationSection: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var isHovered: Bool = false
    @Binding var buttons: SaveButtons

    var body: some View {
        Section {
            Cell(
                leading: "Seniority Level", trailingKeys: \JobApp.seniorityLevel,
                formTrailingKeys: \JobAppForm.seniorityLevel, isEditing: $buttons.edit
            )
            Cell(
                leading: "Employment Type", trailingKeys: \JobApp.employmentType,
                formTrailingKeys: \JobAppForm.employmentType, isEditing: $buttons.edit
            )
            Cell(
                leading: "Job Function", trailingKeys: \JobApp.jobFunction,
                formTrailingKeys: \JobAppForm.jobFunction, isEditing: $buttons.edit
            )
            Cell(
                leading: "Industries", trailingKeys: \JobApp.industries,
                formTrailingKeys: \JobAppForm.industries, isEditing: $buttons.edit
            )
        }
        .insetGroupedStyle(header: Text("Job Information"))
    }
}
