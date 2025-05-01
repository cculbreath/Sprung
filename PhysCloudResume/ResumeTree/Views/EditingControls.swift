
//  EditingControls.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/29/25.
//

import SwiftUI

struct EditingControls: View {
    @Binding var isEditing: Bool
    @Binding var tempName: String
    @Binding var tempValue: String
    @State var isHoveringSave: Bool = false
    @State var isHoveringCancel: Bool = false

    var saveChanges: () -> Void
    var cancelChanges: () -> Void
    var deleteNode: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Button(action: {
                    isEditing = false
                    deleteNode()
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(PlainButtonStyle())

                if !tempValue.isEmpty && !tempName.isEmpty {
                    VStack {
                        TextField("Name", text: $tempName)
                        TextEditor(text: $tempValue)
                            .frame(minHeight: 100)
                            .padding(5)
                            .background(Color.primary.opacity(0.1))
                            .cornerRadius(5)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    TextEditor(text: $tempValue)
                        .frame(minHeight: 100)
                        .padding(5)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(5)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 10) {
                Button(action: saveChanges) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(isHoveringSave ? .green : .secondary)
                        .font(.system(size: 14))
                }.onHover { hovering in
                    isHoveringSave = hovering
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: cancelChanges) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(isHoveringCancel ? .red : .secondary)
                        .font(.system(size: 14))
                }.onHover { hovering in
                    isHoveringCancel = hovering
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
