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
    @State private var isValidJSON: Bool = true

    // Optional ResModel to determine if we're editing
    var resModelToEdit: ResModel?

    // State variables
    @State private var formJson: String = ""
    @State private var formResumeText: String = ""
    @State private var formName: String = ""
    @State private var selectedStyle: String = "Typewriter" // initial fallback
    
    // Template customization state
    @State private var customTemplateHTML: String = ""
    @State private var customTemplateText: String = ""
    @State private var templateName: String = ""
    @State private var showAdvancedTemplates: Bool = false

    // Using AppStorage to persist the available styles (as a comma-separated string)
    @AppStorage("availableStyles") private var availableStylesString: String = "Typewriter"
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
                        HStack {
                            Text("JSON Data")
                                .font(.headline)
                            Spacer()
                            if !isValidJSON {
                                Text("⚠️ Invalid JSON format")
                                    .foregroundColor(.red)
                                    .font(.callout)
                                    .padding(.vertical, 5)
                            }
                        }.frame(maxWidth: .infinity)

                        JsonValidatingTextEditor(sourceContent: $formJson, isValidJSON: $isValidJSON)
                            .frame(height: 150)

                        // Display warning when JSON is invalid
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
                    
                    // Template Settings Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Template Settings")
                                .font(.headline)
                            Spacer()
                            Button(action: { showAdvancedTemplates.toggle() }) {
                                Image(systemName: showAdvancedTemplates ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        
                        if showAdvancedTemplates {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Custom Template Name (optional)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Template name", text: $templateName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Text("Custom HTML Template (optional)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                CustomTextEditor(sourceContent: $customTemplateHTML)
                                    .frame(height: 100)
                                
                                Text("Custom Text Template (optional)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                CustomTextEditor(sourceContent: $customTemplateText)
                                    .frame(height: 80)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
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
                .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty || !isValidJSON)
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
            customTemplateHTML = resModel.customTemplateHTML ?? ""
            customTemplateText = resModel.customTemplateText ?? ""
            templateName = resModel.templateName ?? ""
        }
    }

    // Save or update ResModel
    private func saveResModel() {
        let trimmedName = formName.trimmingCharacters(in: .whitespaces)

        if let resModel = resModelToEdit {
            let updatedResModel = resModel
            updatedResModel.name = trimmedName
            updatedResModel.json = formJson
            updatedResModel.style = selectedStyle
            updatedResModel.renderedResumeText = formResumeText
            updatedResModel.customTemplateHTML = customTemplateHTML.isEmpty ? nil : customTemplateHTML
            updatedResModel.customTemplateText = customTemplateText.isEmpty ? nil : customTemplateText
            updatedResModel.templateName = templateName.isEmpty ? nil : templateName
            resModelStore.updateResModel(updatedResModel)
        } else {
            let newResModel = ResModel(
                name: trimmedName,
                json: formJson,
                renderedResumeText: formResumeText,
                style: selectedStyle
            )
            newResModel.customTemplateHTML = customTemplateHTML.isEmpty ? nil : customTemplateHTML
            newResModel.customTemplateText = customTemplateText.isEmpty ? nil : customTemplateText
            newResModel.templateName = templateName.isEmpty ? nil : templateName
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
