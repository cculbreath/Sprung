//
//  ResRefFormView.swift
//  Sprung
//
//
import SwiftUI
import UniformTypeIdentifiers
struct ResRefFormView: View {
    @State private var isTargeted: Bool = false
    @State var sourceName: String = ""
    @State var sourceContent: String = ""
    @State var enabledByDefault: Bool = true
    @State private var dropErrorMessage: String?
    @Binding var isSheetPresented: Bool
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    var existingResRef: ResRef?
    init(isSheetPresented: Binding<Bool>, existingResRef: ResRef? = nil) {
        _isSheetPresented = isSheetPresented
        self.existingResRef = existingResRef
    }
    var body: some View {
        @Bindable var resRefStore = resRefStore
        VStack {
            Text(existingResRef == nil ? "Add Knowledge Card" : "Edit Knowledge Card")
                .font(.headline)
                .padding(.top)
            ScrollView { // Prevents unnecessary Form padding
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Name:")
                            .frame(width: 150, alignment: .trailing)
                        TextField("", text: $sourceName)
                            .frame(maxWidth: .infinity)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    HStack(alignment: .top) {
                        Text("Content:")
                            .frame(width: 150, alignment: .trailing)
                        CustomTextEditor(sourceContent: $sourceContent)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
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
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            handleOnDrop(providers: providers)
        }
        .onAppear {
            if let resRef = existingResRef {
                self.sourceName = resRef.name
                self.sourceContent = resRef.content
                self.enabledByDefault = resRef.enabledByDefault
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { dropErrorMessage != nil },
            set: { if !$0 { dropErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                dropErrorMessage = nil
            }
        } message: {
            Text(dropErrorMessage ?? "Unknown error")
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
        var didRequestLoad = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didRequestLoad = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let urlData = item as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil)
                else {
                    Logger.error("❌ Failed to resolve dropped file URL")
                    showDropError("Could not access the dropped file.")
                    return
                }
                guard isSupportedTextFile(url) else {
                    Logger.warning("⚠️ Unsupported file type dropped: \(url.pathExtension)")
                    showDropError("Unsupported file type: \(url.pathExtension.uppercased()). Please drop a plain text, Markdown, or JSON file.")
                    return
                }
                Task.detached {
                    do {
                        let text = try String(contentsOf: url, encoding: .utf8)
                        let fileName = url.deletingPathExtension().lastPathComponent
                        await MainActor.run {
                            self.sourceName = fileName
                            self.sourceContent = text
                            self.dropErrorMessage = nil
                            saveRefForm()
                            resetRefForm()
                            closePopup()
                        }
                    } catch {
                        Logger.error("❌ Failed to load dropped file as UTF-8 text: \(error.localizedDescription)")
                        await MainActor.run {
                            self.showDropError("Could not read the file using UTF-8 encoding.")
                        }
                    }
                }
            }
        }
        return didRequestLoad
    }
    private func closePopup() {
        isSheetPresented = false
    }
    private func isSupportedTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .plainText) ||
                type.conforms(to: .utf8PlainText) ||
                type.conforms(to: .utf16PlainText) ||
                type.conforms(to: .json) {
                return true
            }
            if let markdown = UTType(filenameExtension: "md"), type == markdown { return true }
            if let markdownLong = UTType(filenameExtension: "markdown"), type == markdownLong { return true }
        }
        let allowedExtensions: Set<String> = ["txt", "md", "markdown", "json", "csv", "yaml", "yml"]
        return allowedExtensions.contains(ext)
    }
    private func showDropError(_ message: String) {
        DispatchQueue.main.async {
            self.dropErrorMessage = message
        }
    }
}
