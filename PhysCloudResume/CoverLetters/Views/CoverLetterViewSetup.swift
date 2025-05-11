//
//  CoverLetterViewSetup.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

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
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) { // .automatic is suitable for macOS toolbars
                // Content from the original CoverLetterToolbar.swift
                // The Spacer is no longer needed as placement handles alignment.

                CoverLetterAiView(
                    buttons: $coverLetterButtons,
                    refresh: $refresh
                )

                Button(action: {
                    coverLetterButtons.showInspector.toggle()
                }) {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
                // .onAppear { print("Toolbar Cover Letter") } // This was on the button in CoverLetterToolbar
            }
        }
        .onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, _ in
            // Existing onChange logic
        }
    }
}
