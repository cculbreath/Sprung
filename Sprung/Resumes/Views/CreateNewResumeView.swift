//
//  CreateNewResumeView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//

import SwiftData
import SwiftUI

struct CreateNewResumeView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(TemplateStore.self) private var templateStore: TemplateStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Binding var refresh: Bool

    // State variables
    @State private var selectedTemplateID: UUID?
    @State private var showErrorMessage = false
    @State private var errorMessage = ""

    var body: some View {
        // Safely unwrap the selected job application
        if let selApp: JobApp = jobAppStore.selectedApp {
            VStack(spacing: 20) {
                Text("Create a New Résumé")
                    .font(.title)
                    .padding(.top)

                // Standard SwiftUI Picker - going back to basics
                let templates = templateStore.templates()
                Picker("Select Template", selection: $selectedTemplateID) {
                    Text("Select a template").tag(nil as UUID?)
                    ForEach(templates) { template in
                        Text(template.name).tag(template.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .padding()

                // Display selected model info
                if let template = templates.first(where: { $0.id == selectedTemplateID }) {
                    Text("Selected: \(template.name)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else if !templates.isEmpty {
                    Text("No template selected")
                        .font(.subheadline)
                        .foregroundColor(.red)
                } else {
                    Text("No templates available")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                // Standard SwiftUI Button - using the original approach
                Button(action: {
                    createResume(with: selApp, templates: templates)
                }) {
                    Text("Create Résumé")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .buttonStyle(PlainButtonStyle())

                // Error message display
                if showErrorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.callout)
                        .padding()
                }
            }
            .padding()
            .onAppear {
                // Set default selection
                let templates = templateStore.templates()
                if selectedTemplateID == nil, let first = templates.first {
                    selectedTemplateID = first.id
                }
            }
        } else {
            Text("No job application selected.")
                .foregroundColor(.red)
                .padding()
        }
    }

    // Separate function to handle resume creation
    private func createResume(with jobApp: JobApp, templates: [Template]) {
        guard let templateID = selectedTemplateID,
              let template = templates.first(where: { $0.id == templateID }) else {
            errorMessage = "Please select a template first"
            showErrorMessage = true
            return
        }

        if resStore.create(
            jobApp: jobApp,
            sources: resRefStore.defaultSources,
            template: template
        ) != nil {
            // Update UI
            refresh.toggle()

            // Ensure the UI updates fully
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                refresh.toggle()
            }
            showErrorMessage = false
        } else {
            errorMessage = "Failed to create resume"
            showErrorMessage = true
        }
    }
}
