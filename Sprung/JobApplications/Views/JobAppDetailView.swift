//
//  JobAppDetailView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//

import SwiftData
import SwiftUI

struct JobAppDetailView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore // Explicit
    @Binding var tab: TabList
    @Binding var buttons: SaveButtons
    @State private var showingDeleteConfirmation: Bool = false

    var body: some View {
        ScrollView {
            let _ = jobAppStore.form
            if jobAppStore.selectedApp != nil {
                VStack {
                    HeaderView(
                        showingDeleteConfirmation: $showingDeleteConfirmation, buttons: $buttons, tab: $tab
                    )

                    JobAppPostingDetailsSection(buttons: $buttons)

                    JobAppDescriptionSection(buttons: $buttons)

                    JobAppInformationSection(buttons: $buttons)

                    ApplySection(buttons: $buttons)
                }
                .padding(.horizontal).padding(.vertical)
                .onChange(of: buttons.edit) { _, newValue in
                    if newValue {
                        jobAppStore.editWithForm()
                    }
                }
                .onChange(of: buttons.cancel) { _, newValue in
                    if newValue && buttons.edit {
                        jobAppStore.cancelFormEdit() // revert changes
                        buttons.edit = false
                        buttons.cancel = false
                    }
                }
                .onChange(of: buttons.save) { _, newValue in
                    if newValue && buttons.edit {
                        jobAppStore.saveForm()

                        buttons.edit = false
                        buttons.save = false
                    }
                }
            } else {
                Text("No job application selected")
                    .padding()
            }
        }
    }
}
