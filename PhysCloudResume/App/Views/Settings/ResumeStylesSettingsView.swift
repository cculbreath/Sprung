//
//  ResumeStylesSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import SwiftUI

struct ResumeStylesSettingsView: View {
    // AppStorage property specific to this view
    @AppStorage("availableStyles") private var availableStylesString: String = "Typewriter"

    // State for managing the list of styles and adding new ones
    @State private var availableStyles: [String] = []
    @State private var newStyle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Available Résumé Styles")
                .font(.headline)
                .padding(.bottom, 5)

            // List of existing styles with delete buttons
            ForEach(availableStyles, id: \.self) { style in
                HStack {
                    Text(style)
                    Spacer()
                    // Only show delete button if there's more than one style
                    if availableStyles.count > 1 {
                        Button {
                            removeStyle(style)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red) // Make delete button red
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help("Remove style '\(style)'")
                    }
                }
                Divider() // Add divider between styles
            }

            // Input field and button to add a new style
            HStack {
                TextField("Add New Style Name", text: $newStyle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(addNewStyle) // Allow adding by pressing Enter

                Button(action: addNewStyle) {
                    Image(systemName: "plus.circle.fill") // Use filled plus icon
                        .foregroundColor(.green) // Make add button green
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(newStyle.trimmingCharacters(in: .whitespaces).isEmpty) // Disable if field is empty
                .help("Add the new style")
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
        )
        .onAppear(perform: loadAvailableStyles) // Load styles when the view appears
    }

    // Load styles from AppStorage string
    private func loadAvailableStyles() {
        availableStyles = availableStylesString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } // Filter out empty strings
        // Ensure "Typewriter" is always present if the list becomes empty
        if availableStyles.isEmpty {
            availableStyles = ["Typewriter"]
            saveStyles() // Save the default back if needed
        }
    }

    // Add a new style to the list and save to AppStorage
    private func addNewStyle() {
        let trimmedStyle = newStyle.trimmingCharacters(in: .whitespaces)
        // Prevent adding empty or duplicate styles
        guard !trimmedStyle.isEmpty, !availableStyles.contains(trimmedStyle) else {
            newStyle = "" // Clear input field even if not added
            return
        }
        availableStyles.append(trimmedStyle)
        saveStyles()
        newStyle = "" // Clear input field after adding
    }

    // Remove a style from the list and save to AppStorage
    private func removeStyle(_ styleToRemove: String) {
        availableStyles.removeAll { $0 == styleToRemove }
        // Ensure "Typewriter" remains if it's the last one being removed
        if availableStyles.isEmpty {
            availableStyles = ["Typewriter"]
        }
        saveStyles()
    }

    // Save the current list of styles back to the AppStorage string
    private func saveStyles() {
        availableStylesString = availableStyles.joined(separator: ", ")
    }
}
