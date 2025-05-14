//
//  ResumeViewSetup.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

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

            // Force refresh when resume status changes
            if newVal {
                DispatchQueue.main.async {
                    refresh.toggle()
                }
            }
        }

//            .onChange(of: selectedApp?.resumes.count) {
//                if selectedApp?.resumes.count == 0 {
//                    $refresh.wrappedValue = false
//                }
//              Logger.debug(
//                "count tog \(selectedApp?.resumes.count)"
//              ) // Force update when resumes change
//            }
//            .onChange(of: selectedApp.selectedRes) {
//                Logger.debug("change tog") // Force update when selected resume changes
//            }
//            .onChange(of: selectedApp) {
//                Logger.debug("change detected")
//            }
    }
}
