import SwiftUI

struct ResumeViewSetup: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool
    @State private var isWide = false
    @State var currentTab: TabList

    var body: some View {
        VStack {
            if jobAppStore.selectedApp?.hasAnyRes ?? false {
                ResumeSplitView(isWide: $isWide, tab: $currentTab, resumeButtons: $resumeButtons, refresh: $refresh)
            } else {
                CreateNewResumeView(refresh: $refresh)
            }
        }
        .id(jobAppStore.selectedApp?.id)
        .onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, newVal in
            print(newVal ? "✅ Job app now has resumes" : "⚠️ Job app has no resumes")

            // Force refresh when resume status changes
            if newVal {
                DispatchQueue.main.async {
                    print("🔄 Resume status changed - forcing refresh")
                    refresh.toggle()
                }
            }
        }

//            .onChange(of: selectedApp?.resumes.count) {
//                if selectedApp?.resumes.count == 0 {
//                    $refresh.wrappedValue = false
//                }
//              print(
//                "count tog \(selectedApp?.resumes.count)"
//              ) // Force update when resumes change
//            }
//            .onChange(of: selectedApp.selectedRes) {
//                print("change tog") // Force update when selected resume changes
//            }
//            .onChange(of: selectedApp) {
//                print("change detected")
//            }
    }
}
