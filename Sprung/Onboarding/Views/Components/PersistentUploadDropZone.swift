//
//  PersistentUploadDropZone.swift
//  Sprung
//
//  A compact, always-visible drop zone for uploading documents during Phase 2.
//  This allows users to upload files at any time without waiting for the LLM to present an upload form.
//  Also includes a button for adding git repositories for code analysis.
//
import SwiftUI
import UniformTypeIdentifiers

struct PersistentUploadDropZone: View {
    let onDropFiles: ([URL]) -> Void
    let onSelectFiles: () -> Void
    let onSelectGitRepo: ((URL) -> Void)?

    @State private var isDropTargetHighlighted = false

    private let acceptedExtensions = Set(["pdf", "docx", "txt", "pptx", "png", "jpg", "jpeg", "md", "json", "gif", "webp", "heic"])

    /// UTTypes accepted for drag and drop - includes file URLs and direct image types
    private let acceptedDropTypes: [UTType] = [
        .fileURL,
        .image,
        .png,
        .jpeg,
        .gif,
        .heic
    ]

    init(
        onDropFiles: @escaping ([URL]) -> Void,
        onSelectFiles: @escaping () -> Void,
        onSelectGitRepo: ((URL) -> Void)? = nil
    ) {
        self.onDropFiles = onDropFiles
        self.onSelectFiles = onSelectFiles
        self.onSelectGitRepo = onSelectGitRepo
    }

    var body: some View {
        VStack(spacing: 10) {
            // Document upload section
            documentUploadRow

            // Git repo section (if handler provided)
            if onSelectGitRepo != nil {
                gitRepoRow
            }
        }
    }

    private var documentUploadRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isDropTargetHighlighted ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Drop files here anytime")
                    .font(.subheadline.weight(.medium))
                Text("or click to browse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onSelectFiles) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDropTargetHighlighted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isDropTargetHighlighted ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { onSelectFiles() }
        .onDrop(of: acceptedDropTypes, isTargeted: $isDropTargetHighlighted, perform: handleDrop(providers:))
    }

    private var gitRepoRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add code repository")
                    .font(.subheadline.weight(.medium))
                Text("Analyze skills from git history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: selectGitRepository) {
                Label("Select", systemImage: "folder.badge.gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func selectGitRepository() {
        let panel = NSOpenPanel()
        panel.title = "Select Git Repository"
        panel.message = "Choose the root folder of a git repository to analyze"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            // Verify it's a git repo
            let gitDir = url.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                onSelectGitRepo?(url)
            } else {
                Logger.warning("Selected directory is not a git repository: \(url.path)", category: .ai)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Logger.debug("📥 Drop received with \(providers.count) provider(s)", category: .ai)

        // Check what types each provider supports
        for (index, provider) in providers.enumerated() {
            let types = provider.registeredTypeIdentifiers
            Logger.debug("📥 Provider \(index): \(types.joined(separator: ", "))", category: .ai)
        }

        Task {
            var collected: [URL] = []

            for provider in providers {
                // Try file URL first (e.g., from Finder)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = await loadFileURL(from: provider) {
                        if isFileTypeAllowed(url) {
                            collected.append(url)
                            Logger.debug("📥 Loaded file URL: \(url.lastPathComponent)", category: .ai)
                        } else {
                            Logger.debug("📥 Rejected file (type not allowed): \(url.lastPathComponent)", category: .ai)
                        }
                    }
                }
                // Try loading as image data (e.g., from Photos app or browser)
                else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = await loadImageData(from: provider) {
                        collected.append(url)
                        Logger.debug("📥 Loaded image data, saved to: \(url.lastPathComponent)", category: .ai)
                    }
                }
            }

            if !collected.isEmpty {
                Logger.info("📥 Processing \(collected.count) dropped file(s)", category: .ai)
                await MainActor.run {
                    onDropFiles(collected)
                }
            } else {
                Logger.warning("📥 No valid files found in drop", category: .ai)
            }
        }
        return true
    }

    private func isFileTypeAllowed(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return acceptedExtensions.contains(fileExtension)
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    Logger.debug("📥 Error loading file URL: \(error.localizedDescription)", category: .ai)
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8),
                          let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Load image data and save to a temporary file
    private func loadImageData(from provider: NSItemProvider) async -> URL? {
        // Try specific image types first, then fall back to generic image
        let imageTypes: [UTType] = [.png, .jpeg, .gif, .heic, .image]

        for imageType in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(imageType.identifier) {
                if let url = await loadImageOfType(imageType, from: provider) {
                    return url
                }
            }
        }
        return nil
    }

    private func loadImageOfType(_ type: UTType, from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    Logger.debug("📥 Error loading image data (\(type.identifier)): \(error.localizedDescription)", category: .ai)
                    continuation.resume(returning: nil)
                    return
                }

                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }

                // Determine file extension
                let ext: String
                switch type {
                case .png: ext = "png"
                case .jpeg: ext = "jpg"
                case .gif: ext = "gif"
                case .heic: ext = "heic"
                default: ext = "png" // Default to PNG for generic image type
                }

                // Save to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "dropped_image_\(UUID().uuidString).\(ext)"
                let tempURL = tempDir.appendingPathComponent(filename)

                do {
                    try data.write(to: tempURL)
                    Logger.debug("📥 Saved dropped image to temp file: \(filename)", category: .ai)
                    continuation.resume(returning: tempURL)
                } catch {
                    Logger.error("📥 Failed to save dropped image: \(error.localizedDescription)", category: .ai)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
