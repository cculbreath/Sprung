//
//  CreateNewResumeView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import SwiftData
import SwiftUI

struct CreateNewResumeView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Binding var refresh: Bool

    // State variables
    @State private var selectedJsonModel: ResModel? = nil
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
                Picker("Select Template", selection: $selectedJsonModel) {
                    Text("Select a template").tag(nil as ResModel?)
                    ForEach(resModelStore.resModels) { model in
                        Text(model.name).tag(model as ResModel?)
                    }
                }
                .pickerStyle(.menu)
                .padding()

                // Display selected model info
                if let selectedModel = selectedJsonModel {
                    Text("Selected: \(selectedModel.style)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("No template selected")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }

                // Standard SwiftUI Button - using the original approach
                Button(action: {
                    createResume(with: selApp)
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
                if selectedJsonModel == nil, let firstModel = resModelStore.resModels.first {
                    selectedJsonModel = firstModel
                }
            }
        } else {
            Text("No job application selected.")
                .foregroundColor(.red)
                .padding()
        }
    }

    // Separate function to handle resume creation
    private func createResume(with jobApp: JobApp) {
        guard let selectedModel = selectedJsonModel else {
            errorMessage = "Please select a template first"
            showErrorMessage = true
            return
        }

        if let newResume = resStore.create(
            jobApp: jobApp,
            sources: resRefStore.defaultSources,
            model: selectedModel
        ) {
            newResume.debounceExport()

            // Update UI
            refresh.toggle()

            // Ensure the UI updates fully
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                refresh.toggle()
            }
        } else {
            errorMessage = "Failed to create resume"
            showErrorMessage = true
        }
    }
}
