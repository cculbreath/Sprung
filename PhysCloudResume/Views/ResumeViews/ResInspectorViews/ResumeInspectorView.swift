//
//  ResumeInspectorView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/30/25.
//

import SwiftUI

struct ResumeInspectorView: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Binding var refresh: Bool
    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            @Bindable var selApp = selApp

            VStack {
                ResumeInspectorListView(
                    listSelection: $selApp.selectedRes,
                    resumes: $selApp.resumes
                )
                ResInspectorToggleView(res: $selApp.selectedRes)
                CreateNewResumeView(refresh: $refresh)
            }

        } else {
            Text("No application selected.")
        }
    }
}
