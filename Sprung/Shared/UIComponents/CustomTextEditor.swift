//
//  CustomTextEditor.swift
//  Sprung
//
//
import SwiftUI
struct CustomTextEditor: View {
    @Binding var sourceContent: String
    var placeholder: String?
    var minimumHeight: CGFloat = 130
    var maximumHeight: CGFloat? = 150
    var onChange: (() -> Void)?
    @FocusState private var isFocused: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            if sourceContent.isEmpty, let placeholder, !placeholder.isEmpty {
                Text(placeholder)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
            }
            TextEditor(text: $sourceContent)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .focused($isFocused)
        }
        .frame(minHeight: minimumHeight, maxHeight: maximumHeight)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.blue : Color.secondary, lineWidth: 1)
        )
        .onTapGesture { isFocused = true }
        .onChange(of: sourceContent) { _, _ in onChange?() }
    }
}
