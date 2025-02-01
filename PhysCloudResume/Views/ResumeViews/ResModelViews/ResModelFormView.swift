//
//  ResModelFormView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import SwiftUI

struct ResModelFormView: View {
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @Binding var sheetPresented: Bool

    // Optional ResModel to determine if we're editing
    var resModelToEdit: ResModel?

    // State variables
    @State private var formJson: String = ""
    @State private var formResumeText: String = ""
    @State private var formName: String = ""
    @State private var selectedStyle: String = ResModel.defaultStyle // State for the chosen style

    // Using AppStorage to persist the available styles (as a comma-separated string)
    @AppStorage("availableStyles") private var availableStylesString: String = ResModel.defaultStyle
    @State private var availableStyles: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Text(resModelToEdit == nil ? "New Resume Model" : "Edit Resume Model")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.leading, 16)

                Spacer()

                Button(action: { sheetPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .imageScale(.large)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 16)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Name Field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.headline)
                        TextField("Enter name", text: $formName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal, 20) // Added horizontal padding

                    // JSON Data
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JSON Data")
                            .font(.headline)
                        CustomTextEditor(sourceContent: $formJson)
                            .frame(minHeight: 120)
                    }
                    .padding(.horizontal, 20) // Added horizontal padding

                    // Resume Text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Resume Text")
                            .font(.headline)
                        CustomTextEditor(sourceContent: $formResumeText)
                            .frame(minHeight: 120)
                    }
                    .padding(.horizontal, 20) // Added horizontal padding

                    HStack {
                        Spacer()
                        Text("Style:")
                        Picker("", selection: $selectedStyle) {
                            ForEach(availableStyles, id: \.self) { style in
                                Text(style)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        Spacer()
                    }
                    .padding(.horizontal)
                    // Delete Button (if editing)
                }
                .padding(.vertical)
            }
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.windowBackgroundColor)) // macOS window background gray

            Divider()

            // Bottom Toolbar
            HStack {
                if resModelToEdit != nil {
                    Button(action: deleteResModel) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                    }.buttonStyle(.bordered)
                }
                Spacer()
                Button("Cancel") {
                    sheetPresented = false
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    saveResModel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor)) // macOS standard background
        .onAppear {
            availableStyles = availableStylesString
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            // If the current selectedStyle is not in availableStyles, default it
            if !availableStyles.contains(selectedStyle), let firstStyle = availableStyles.first {
                selectedStyle = firstStyle
            }
            populateFields()
        }
    }

    // Populate fields if editing
    private func populateFields() {
        if let resModel = resModelToEdit {
            formName = resModel.name
            formJson = resModel.json
            formResumeText = resModel.renderedResumeText
            selectedStyle = resModel.style
        }
    }

    // Save or update ResModel
    private func saveResModel() {
        let trimmedName = formName.trimmingCharacters(in: .whitespaces)

        if let resModel = resModelToEdit {
            var updatedResModel = resModel
            updatedResModel.name = trimmedName
            updatedResModel.json = formJson
            updatedResModel.style = selectedStyle
            updatedResModel.renderedResumeText = formResumeText
            resModelStore.updateResModel(updatedResModel)
        } else {
            let newResModel = ResModel(
                name: trimmedName,
                json: formJson,
                renderedResumeText: formResumeText,
                style: ResModel.defaultStyle
            )
            resModelStore.addResModel(newResModel)
        }

        sheetPresented = false
    }

    // Delete ResModel
    private func deleteResModel() {
        guard let resModel = resModelToEdit else { return }
        resModelStore.deleteResModel(resModel)
        sheetPresented = false
    }
}
