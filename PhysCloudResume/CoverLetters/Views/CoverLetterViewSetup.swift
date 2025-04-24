import SwiftUI

struct CoverLetterViewSetup: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Binding var coverLetterButtons: CoverLetterButtons
    @Binding var refresh: Bool

    var body: some View {
        VStack {
            if jobAppStore.selectedApp?.hasAnyRes ?? false {
                CoverLetterView(buttons: $coverLetterButtons)
            } else {
                CreateNewResumeView(refresh: $refresh)
            }
        }.onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, newVal in
        }
    }
}
