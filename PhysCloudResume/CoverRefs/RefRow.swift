//
//  RefRow.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on .
//

import SwiftUI

struct RefRow: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Bindable var cL: CoverLetter
    @Bindable var element: CoverRef
    @Bindable var coverRefStore: CoverRefStore
    @State var isButtonHovering = false
    var showPreview: Bool

    var body: some View {
        HStack {
            Toggle(
                isOn: Binding<Bool>(
                    get: {
                        cL.enabledRefs.contains { $0.id == element.id }
                    },
                    set: { isEnabled in
                        guard let oldCL = coverLetterStore.cL else { return }

                        if oldCL.generated {
                            // Make a new copy
                            let newCL = coverLetterStore.createDuplicate(letter: oldCL)
                            if isEnabled {
                                newCL.enabledRefs.append(element)
                            } else {
                                newCL.enabledRefs.removeAll { $0.id == element.id }
                            }
                            coverLetterStore.cL = newCL
                        } else {
                            // Mutate the existing cL in place
                            if isEnabled {
                                cL.enabledRefs.append(element)
                            } else {
                                cL.enabledRefs.removeAll { $0.id == element.id }
                            }
                        }
                    }
                )
            ) {
                HStack {
                    // Show either content or name
                    if showPreview {
                        Text(element.content)
                            .contextMenu {
                                Button(role: .destructive) {
                                    coverRefStore.deleteCoverRef(element)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    } else {
                        Text(element.name)
                            .contextMenu {
                                Button(role: .destructive) {
                                    coverRefStore.deleteCoverRef(element)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }

                    Spacer()

                    // A trash button for quick deletion
                    Button(action: {
                        coverRefStore.deleteCoverRef(element)
                    }) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(isButtonHovering ? .red : .gray)
                            .font(.system(size: 15))
                            .padding(2)
                            .background(
                                isButtonHovering
                                    ? Color.red.opacity(0.3)
                                    : Color.gray.opacity(0.3)
                            )
                            .cornerRadius(5)
                    }
                    .onHover { hover in
                        isButtonHovering = hover
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(4)
                }
            }
        }
    }
}
