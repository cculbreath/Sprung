//
//  ResInspectorToggleView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import AppKit // Import AppKit to use NSCursor
import SwiftData
import SwiftUI

struct ResInspectorToggleView: View {
    // Access the ResRefStore from the environment.
    @Environment(ResRefStore.self) var resRefStore: ResRefStore
    @Query(sort: \ResRef.name) private var resRefs: [ResRef]
    // Bind to the Resume model.
    @Binding var res: Resume?

    // Define a grid layout with two flexible columns.
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    // Helper function to create the binding for a ResRef
    private func createBinding(for resRef: ResRef, in resume: Resume) -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                // Check if this ResRef is in the resume's enabledSources.
                resume.enabledSources.contains { $0.id == resRef.id }
            },
            set: { newValue in
                if newValue {
                    // Add the ResRef if it isn't already present.
                    if !resume.enabledSources.contains(where: { $0.id == resRef.id }) {
                        resume.enabledSources.append(resRef)
                    }
                } else {
                    // Remove the ResRef if it is present.
                    resume.enabledSources.removeAll { $0.id == resRef.id }
                }
            }
        )
    }

    var body: some View {
        if let resume = res {
            VStack {
                // Centered headline
                Text("Enabled Background Sources")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 2)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
                    ForEach(resRefs, id: \.id) { resRef in
                        ResRefToggleCell(
                            resRef: resRef,
                            isEnabled: createBinding(for: resRef, in: resume)
                        )
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.3))
//            .overlay(
//              Rectangle()
//                .stroke(Color.white.opacity(0.5), lineWidth: 1)
//            )      .frame(alignment: .top)
        }
    }
}

struct ResRefToggleCell: View {
    var resRef: ResRef
    @Binding var isEnabled: Bool
    @State private var isHovered: Bool = false

    var body: some View {
        HStack {
            Toggle(resRef.name, isOn: $isEnabled)
                .toggleStyle(.checkbox) // macOS default checkbox style.
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(8)
        .background(isHovered ? Color.gray.opacity(0.2) : Color.clear)
        // Removed cornerRadius for a square appearance.
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
