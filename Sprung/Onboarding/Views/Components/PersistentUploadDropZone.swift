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
        .onDrop(of: DropZoneHandler.acceptedDropTypes, isTargeted: $isDropTargetHighlighted) { providers in
            DropZoneHandler.handleDrop(providers: providers, completion: onDropFiles)
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
