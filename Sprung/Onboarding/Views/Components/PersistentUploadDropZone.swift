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
    let onDropFiles: ([URL], LargePDFExtractionMethod?) -> Void
    let onSelectFiles: () -> Void
    let onSelectGitRepo: ((URL) -> Void)?

    @State private var isDropTargetHighlighted = false
    @State private var pendingPDFFiles: [URL] = []
    @State private var showingPDFExtractionChoice = false

    init(
        onDropFiles: @escaping ([URL], LargePDFExtractionMethod?) -> Void,
        onSelectFiles: @escaping () -> Void,
        onSelectGitRepo: ((URL) -> Void)? = nil
    ) {
        self.onDropFiles = onDropFiles
        self.onSelectFiles = onSelectFiles
        self.onSelectGitRepo = onSelectGitRepo
    }

    var body: some View {
        VStack(spacing: 10) {
            // PDF extraction method choice UI (when PDFs are dropped)
            if showingPDFExtractionChoice {
                pdfExtractionChoiceRow
            }

            // Document upload section
            documentUploadRow

            // Git repo section (if handler provided)
            if onSelectGitRepo != nil {
                gitRepoRow
            }
        }
    }

    private var pdfExtractionChoiceRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.blue)
                Text("PDF detected (\(formatSize(pendingPDFFiles.first)))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(action: cancelPDFUpload) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Choose extraction method:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(LargePDFExtractionMethod.allCases, id: \.self) { method in
                    Button(action: { selectExtractionMethod(method) }) {
                        VStack(spacing: 4) {
                            Text(method.displayName)
                                .font(.caption.weight(.medium))
                            Text(method.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    private func formatSize(_ url: URL?) -> String {
        guard let url = url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else {
            return "unknown size"
        }
        let mb = Double(size) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }

    private func handleFilesSelected(_ urls: [URL]) {
        // Check for any PDFs - offer extraction method choice for all PDFs
        let pdfFiles = urls.filter { url in
            url.pathExtension.lowercased() == "pdf"
        }

        if !pdfFiles.isEmpty {
            // Show extraction method choice for PDFs
            pendingPDFFiles = urls
            showingPDFExtractionChoice = true
        } else {
            // Process non-PDF files normally
            onDropFiles(urls, nil)
        }
    }

    private func selectExtractionMethod(_ method: LargePDFExtractionMethod) {
        let files = pendingPDFFiles
        pendingPDFFiles = []
        showingPDFExtractionChoice = false
        onDropFiles(files, method)
    }

    private func cancelPDFUpload() {
        pendingPDFFiles = []
        showingPDFExtractionChoice = false
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
        .onDrop(of: DropZoneHandler.acceptedDropTypes, isTargeted: $isDropTargetHighlighted) { providers in
            DropZoneHandler.handleDrop(providers: providers, completion: handleFilesSelected)
            return true
        }
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
}
