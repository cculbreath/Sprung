//
//  SourceRowView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftUI

struct ResRefRowView: View {
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @State var sourceNode: ResRef
    @State private var isButtonHovering = false

    // State to manage sheet presentation
    @State private var isEditSheetPresented: Bool = false

    var body: some View {
        @Bindable var resRefStore = resRefStore
        HStack {
            // Toggle aligned to the left
            Toggle("", isOn: $sourceNode.enabledByDefault)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
                .padding(.horizontal, 15)

            // Text filling the space
            VStack(alignment: .leading) {
                Text(sourceNode.name)
                    .foregroundColor(sourceNode.enabledByDefault ? .primary : .secondary)
            }
            .onTapGesture {
                // Present the edit sheet when the text is tapped
                isEditSheetPresented = true
            }
            .sheet(isPresented: $isEditSheetPresented) {
                ResRefFormView(
                    isSheetPresented: $isEditSheetPresented,
                    existingResRef: sourceNode
                )
            }

            Spacer() // Pushes the trash button to the right

            // Trash button aligned to the right
            Button(action: {
                resRefStore.deleteResRef(sourceNode)
            }) {
                Image(systemName: "trash.fill")
                    .foregroundColor(isButtonHovering ? .red : .gray)
                    .font(.system(size: 15))
                    .padding(2)
                    .background(isButtonHovering ? Color.red.opacity(0.3) : Color.gray.opacity(0.3))
                    .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(4)
            // Handle hover state (macOS only)
            .onHover { hovering in
                isButtonHovering = hovering
            }
        }
        .padding(.vertical, 5)
    }
}
