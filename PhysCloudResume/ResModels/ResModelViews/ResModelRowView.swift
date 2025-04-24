//
//  ResModelRowView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

//
//  ResSourceRowView 2.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

//
//  SourceRowView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftUI

struct ResModelRowView: View {
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @State var sourceNode: ResModel
    @State private var isButtonHovering = false

    // State to manage sheet presentation
    @State private var isEditSheetPresented: Bool = false

    var body: some View {
        @Bindable var resModelStore = resModelStore
        HStack {
            // Toggle aligned to the left

            // Text filling the space
            VStack(alignment: .trailing) {
                HStack {
                    Text(sourceNode.name)
                    Spacer()
                    Text(sourceNode.style)
                }
            }
            .onTapGesture {
                // Present the edit sheet when the text is tapped
                isEditSheetPresented = true
            }
            .sheet(isPresented: $isEditSheetPresented) {
                ResModelFormView(
                    sheetPresented: $isEditSheetPresented,
                    resModelToEdit: sourceNode
                )
            }

            Spacer().frame(maxWidth: 50) // Pushes the trash button to the right

            // Trash button aligned to the right
            Button(action: {
                resModelStore.deleteResModel(sourceNode)
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
