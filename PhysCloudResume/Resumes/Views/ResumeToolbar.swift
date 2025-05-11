//
//  ResumeToolbar.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftUI

@ToolbarContentBuilder
func resumeToolbarContent(buttons: Binding<ResumeButtons>, selectedResume: Binding<Resume?>) -> some ToolbarContent {
    // AI resume enhancement feature
    ToolbarItem(placement: .automatic) {
        if selectedResume.wrappedValue?.rootNode != nil {
            AiFunctionView(res: selectedResume)
        } else {
            Text(":(")
        }
    }

    // AI resume review feature
    ToolbarItem(placement: .automatic) {
        Button {
            buttons.wrappedValue.showResumeReviewSheet.toggle()
        } label: {
            Label("Review Resume", systemImage: "character.magnify")
        }
        .help("AI Resume Review")
        .disabled(selectedResume.wrappedValue == nil)
        .sheet(isPresented: Binding(
            get: { buttons.wrappedValue.showResumeReviewSheet },
            set: { buttons.wrappedValue.showResumeReviewSheet = $0 }
        )) {
            ResumeReviewSheet(selectedResume: selectedResume)
        }
    }

    // Resume inspector toggle
    ToolbarItem(placement: .primaryAction) {
        Button(action: {
            buttons.wrappedValue.showResumeInspector.toggle()
        }) {
            Label("Toggle Inspector", systemImage: "sidebar.right")
        }
        .onAppear { print("Toolbar Resume") }
    }
}
