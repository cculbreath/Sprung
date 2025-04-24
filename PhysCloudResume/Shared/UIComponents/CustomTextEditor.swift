//
//  CustomTextEditor.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftUI

struct CustomTextEditor: View {
    @Binding var sourceContent: String

    // Internal FocusState
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextEditor(text: $sourceContent)
                .frame(height: 130) // Adjust height as needed
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.blue : Color.secondary, lineWidth: 1))
                .focused($isFocused)
                .onTapGesture { isFocused = true }
                .onChange(of: isFocused) { _ in
                }
        }
        .frame(maxWidth: .infinity, maxHeight: 150)
    }
}
