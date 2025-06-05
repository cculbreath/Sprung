//
//  ChooseBestCoverLetterButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/23/25.
//

import SwiftUI

/// Button for choosing the best cover letter via AI recommendation.
/// NOTE: This component may be legacy - choose best functionality moved to UnifiedToolbar
struct ChooseBestCoverLetterButton: View {
    @Binding var cL: CoverLetter
    let action: () -> Void
    let multiModelAction: () -> Void
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var isOptionPressed = false
    @State private var isProcessing = false

    var body: some View {
        if isProcessing {
            Image(systemName: "wand.and.rays")
                .font(.system(size: 18, weight: .regular))
                .frame(width: 32, height: 32)
                .symbolEffect(.variableColor.iterative.hideInactiveLayers.nonReversing)
        } else {
            Button(action: {
                isProcessing = true
                if isOptionPressed {
                    multiModelAction()
                } else {
                    action()
                }
                // Note: Caller should reset isProcessing when done
            }) {
                Group {
                    if isOptionPressed {
                        Image(systemName: "medal.star.fill")
                    } else {
                        Image(systemName: "medal.star")
                    }
                }
                .font(.system(size: 18, weight: .regular))
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(
                jobAppStore.selectedApp?.coverLetters.count ?? 0 <= 1
                    || cL.writingSamplesString.isEmpty
            )
            .help(
                (jobAppStore.selectedApp?.coverLetters.count ?? 0) <= 1
                    ? "At least two cover letters are required"
                    : cL.writingSamplesString.isEmpty
                    ? "Add writing samples to enable choosing best cover letter"
                    : isOptionPressed
                    ? "Use multiple models to select the best cover letter"
                    : "Select the best cover letter based on style and voice"
            )
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    isOptionPressed = event.modifierFlags.contains(.option)
                    return event
                }
            }
        }
    }
}
