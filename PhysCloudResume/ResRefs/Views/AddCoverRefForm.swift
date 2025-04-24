//
//  AddCoverRefForm.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/12/24.
//

import SwiftUI

struct AddCoverRefForm: View {
    @Bindable var coverRefStore: CoverRefStore
    @State private var newCoverRefName = ""
    @State private var newCoverRefContent = ""
    @State private var newCoverRefEnabledByDefault = true
    @State private var isTargeted: Bool = false

    var type: CoverRefType
    @Bindable var cL: CoverLetter
    @Binding var showMe: Bool
    @FocusState var isFocused: Bool

    var body: some View {
        Form {
            TextField("Name", text: $newCoverRefName)
            TextEditor(text: $newCoverRefContent)
                .padding(5)
                .focusable(true) // (1) Mark it focusable on macOS
                .focused($isFocused)
                .onTapGesture { isFocused = true }
                .onChange(of: isFocused) { print("isFocused changed to:", isFocused) }
                .frame(maxWidth: .infinity, minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            (isTargeted || isFocused) ? .blue : .secondary,
                            lineWidth: (isTargeted || isFocused) ? 2 : 0.25
                        )
                )
            Toggle("Enabled by Default", isOn: $newCoverRefEnabledByDefault)

            HStack {
                Button("Add") {
                    saveForm()
                    // Delay dismissal briefly so SwiftData can publish the new item before unmounting
                    DispatchQueue.main.async {
                        resetForm()
                        dismissForm()
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel") {
                    dismissForm()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 400, maxWidth: 600)
        .navigationTitle("Add \(type == .backgroundFact ? "Background Fact" : "Writing Sample")")
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in handleOnDrop(providers: providers) }
        .onChange(of: isTargeted) { print("isTargeted:", isTargeted) }
    }

    private func saveForm() {
        let newCoverRef = CoverRef(
            name: newCoverRefName,
            content: newCoverRefContent,
            enabledByDefault: newCoverRefEnabledByDefault,
            type: type
        )

//    if self.type == .backgroundFact {
//      coverRefStore.append(newCoverRef)
//    } else if self.type == .writingSample {
//      self.writingSamples.append(newCoverRef)
//    }

        let newRef = coverRefStore.addCoverRef(newCoverRef)

        cL.enabledRefs.append(newRef)
    }

    func handleOnDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let urlData = item as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil)
                    else {
                        return
                    }

                    // Extract the file name
                    let fileName = url.deletingPathExtension().lastPathComponent

                    // Read the file contents
                    do {
                        let text = try String(contentsOf: url, encoding: .utf8)

                        self.newCoverRefName = fileName
                        self.newCoverRefContent = text
                        self.self.newCoverRefEnabledByDefault = true
                        saveForm()

                    } catch {}
                }

                // If we handle a valid file drop, return true
                continue
            } else {
                return false
            }
        }
        resetForm()
        dismissForm()
        return true
    }

    private func resetForm() {
        newCoverRefName = ""
        newCoverRefContent = ""
        newCoverRefEnabledByDefault = true
    }

    private func dismissForm() {
        showMe = false
    }
}
