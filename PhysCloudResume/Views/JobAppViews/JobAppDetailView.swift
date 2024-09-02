import SwiftUI

import SwiftUI
import SwiftData

struct JobAppDetailView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore  // Explicit
    @Binding var tab: TabList
    @Binding var buttons: SaveButtons
    @State private var showingDeleteConfirmation: Bool = false

    var body: some View {
        ScrollView {
            let form = jobAppStore.form
            if let selectedApp = jobAppStore.selectedApp {
                VStack {
                    HeaderView(showingDeleteConfirmation: $showingDeleteConfirmation,  buttons: $buttons, tab: $tab)

                    JobAppPostingDetailsSection(buttons: $buttons)

                    JobAppDescriptionSection(buttons: $buttons)

                    JobAppInformationSection(buttons: $buttons)

                    ApplySection(buttons: $buttons)
                }
                .padding(.horizontal).padding(.vertical)
                .navigationTitle(
                    buttons.edit
                    ? "Editing \(form.job_position) at \(form.company_name)"
                    : "\(selectedApp.job_position) at \(selectedApp.company_name)"
                )
                .onChange(of: buttons.edit) { oldValue, newValue in
                    if newValue {
                        jobAppStore.editWithForm()
                    }
                }
                .onChange(of: buttons.cancel) { oldValue, newValue in
                    if newValue && buttons.edit {
                        jobAppStore.cancelFormEdit() // revert changes
                        buttons.edit = false
                        buttons.cancel = false
                    }
                }
                .onChange(of: buttons.save) { oldValue, newValue in
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
