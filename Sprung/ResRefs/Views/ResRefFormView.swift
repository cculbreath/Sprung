//
//  ResRefFormView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//

import SwiftUI

struct ResRefFormView: View {
    @State private var isTargeted: Bool = false
    @State var sourceName: String = ""
    @State var sourceContent: String = ""
    @State var enabledByDefault: Bool = true
    @Binding var isSheetPresented: Bool

    @Environment(ResRefStore.self) private var resRefStore: ResRefStore

    var existingResRef: ResRef? = nil

    init(isSheetPresented: Binding<Bool>, existingResRef: ResRef? = nil) {
        _isSheetPresented = isSheetPresented

        self.existingResRef = existingResRef
    }

    var body: some View {
        @Bindable var resRefStore = resRefStore
        VStack {
            Text(existingResRef == nil ? "Add New Source" : "Edit Source")
                .font(.headline)
                .padding(.top)

            ScrollView { // Prevents unnecessary Form padding
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Source Name:")
                            .frame(width: 150, alignment: .trailing)
                        TextField("", text: $sourceName)
                            .frame(maxWidth: .infinity)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    HStack(alignment: .top) {
                        Text("Content:")
                            .frame(width: 150, alignment: .trailing)

                        CustomTextEditor(sourceContent: $sourceContent)
                    }

                    HStack {
                        Text("Enabled by Default:")
                            .frame(width: 150, alignment: .trailing)
                        Toggle("", isOn: $enabledByDefault)
                            .toggleStyle(SwitchToggleStyle())
                    }
                }
                .padding()
            }

            HStack {
                Button("Cancel") {
                    isSheetPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    if sourceName.trimmingCharacters(in: .whitespaces).isEmpty { return }
                    saveRefForm()
                    resetRefForm()
                    closePopup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 500) // Fix width explicitly
        .background(Color(NSColor.windowBackgroundColor)) // Matches macOS window background
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            handleOnDrop(providers: providers)
        }
        .onChange(of: isTargeted) { _, _ in
        }
        .onAppear {
            if let resRef = existingResRef {
                self.sourceName = resRef.name
                self.sourceContent = resRef.content
                self.enabledByDefault = resRef.enabledByDefault
            }
        }
    }

    private func saveRefForm() {
        if let resRef = existingResRef {
            let updatedResRef = resRef
            updatedResRef.name = sourceName
            updatedResRef.content = sourceContent
            updatedResRef.enabledByDefault = enabledByDefault

            resRefStore.updateResRef(updatedResRef)
        } else {
            let newSource = ResRef(
                name: sourceName,
                content: sourceContent,
                enabledByDefault: enabledByDefault
            )
            resRefStore.addResRef(newSource)
        }
    }

    private func resetRefForm() {
        sourceName = ""
        sourceContent = ""
        enabledByDefault = true
    }

    private func handleOnDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let urlData = item as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil)
                    else {
                        return
                    }

                    do {
                        let fileName = url.deletingPathExtension().lastPathComponent
                        let text = try String(contentsOf: url, encoding: .utf8)
                        DispatchQueue.main.async {
                            self.sourceName = fileName
                            self.sourceContent = text
                            saveRefForm()
                        }

                    } catch {}
                }

                // Continue to handle other providers
                continue
            } else {
                return false
            }
        }
        resetRefForm()
        closePopup()
        return true
    }

    private func closePopup() {
        isSheetPresented = false
    }
}
