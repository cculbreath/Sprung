import SwiftData
import SwiftUI

struct JobAppDescriptionSection: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var buttons: SaveButtons

    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            @Bindable var boundSelApp = selApp
            Section {
                if buttons.edit {
                    TextField("", text: $boundSelApp.job_description, axis: .vertical)
                        .lineLimit(15 ... 20)
                        .padding(.all, 3)
                } else {
                    Text(boundSelApp.job_description.isEmpty ? "none listed" : boundSelApp.job_description)
                        .textSelection(.enabled)
                        .padding(.all, 3)
                        .foregroundColor(.secondary)
                        .italic(boundSelApp.job_description.isEmpty)
                }
            }
            .insetGroupedStyle(header: Text("Job Description"))
        } else {
            // Handle the case where selectedApp is nil
            Text("No job application selected.")
                .padding()
        }
    }
}
