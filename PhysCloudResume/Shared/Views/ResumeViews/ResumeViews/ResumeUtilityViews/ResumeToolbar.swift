//
//  ResumeToolbar.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/10/24.
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
