//
//  CreateNewResumeView.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/18/24.
//

import SwiftData
import SwiftUI

struct CreateNewResumeView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore

    @Environment(ResStore.self) private var resStore: ResStore
    @Binding var refresh: Bool

    // 1. Define the @State variable for selected JSON model
    @State private var selectedJsonModel: ResModel? = nil // Ensure ResModel conforms to Identifiable

    var body: some View {
        // Safely unwrap the selected job application
        if let selApp: JobApp = jobAppStore.selectedApp {
            VStack(spacing: 20) {
                Text("Create a New Résumé")
                    .font(.title)
                    .padding(.top)

                // 2. Implement the Picker
                Picker("Select JSON Model", selection: $selectedJsonModel) {
                    // Ensure jsonModels conform to Identifiable
                    ForEach(resModelStore.resModels) { model in
                        Text(model.name) // Assuming ResModel has a 'name' property
                            .tag(model as ResModel)
                    }
                }
                .pickerStyle(MenuPickerStyle()) // Choose desired picker style
                .padding()

                // Display selected model (optional)
                if let selectedModel = selectedJsonModel {
                    Text("Selected Model: \(selectedModel.name)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("No JSON model selected.")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }

                // 3. Update the Create Résumé button action
                Button(action: {
                    guard let selectedModel = selectedJsonModel else {
                        // Handle the case where no model is selected
                        print("No JSON model selected. Please select a model before creating a résumé.")
                        return
                    }

                    // Pass defaultSources and selectedJsonModel to the create method
                    resStore.create(jobApp: selApp, sources: resRefStore.defaultSources, model: selectedModel)

                    // Toggle refresh to update the UI if necessary
//                    refresh.toggle()

                    print("Résumé created using model: \(selectedModel.name)")
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
                .buttonStyle(PlainButtonStyle()) // Remove default button styles if needed
            }
            .padding()
            .onAppear {
                print("CreateNewResumeView appeared")

                // Optionally, set a default selection if jsonModels is not empty
                if selectedJsonModel == nil, let firstModel = resModelStore.resModels.first {
                    selectedJsonModel = firstModel
                }
            }
        } else {
            // Handle the case where no job application is selected
            Text("No job application selected.")
                .foregroundColor(.red)
                .padding()
        }
    }
}
