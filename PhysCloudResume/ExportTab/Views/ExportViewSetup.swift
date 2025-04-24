import SwiftUI

struct ExportViewSetup: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Binding var refresh: Bool

    var body: some View {
        VStack {
            if jobAppStore.selectedApp?.hasAnyRes ?? false {
                ResumeExportView()
            } else {
                CreateNewResumeView(refresh: $refresh)
            }
        }.onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, newVal in
            print(newVal ? "change resExists" : "change res doesn't exist")
        }
    }
}
