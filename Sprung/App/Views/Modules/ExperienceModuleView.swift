//
//  ExperienceModuleView.swift
//  Sprung
//
//  Experience Editor module wrapper.
//

import SwiftUI

/// Experience module - wraps existing ExperienceEditorView for embedded use
struct ExperienceModuleView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Experience",
                subtitle: "Manage your work history, education, and skills defaults"
            )

            // Embedded experience editor
            ExperienceEditorView()
        }
    }
}
