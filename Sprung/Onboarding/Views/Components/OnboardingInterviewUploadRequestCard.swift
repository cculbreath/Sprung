import SwiftUI
import UniformTypeIdentifiers
struct UploadRequestCard: View {
    let request: OnboardingUploadRequest
    let onSelectFile: () -> Void
    let onDropFiles: ([URL]) -> Void
    let onDecline: () -> Void
    @State private var isDropTargetHighlighted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.metadata.title)
                .font(.headline)
            Text(request.metadata.instructions)
                .font(.callout)
            if !request.metadata.accepts.isEmpty {
                Text("Accepted types: \(request.metadata.accepts.joined(separator: ", ").uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if request.kind == .linkedIn {
                Text("Paste a LinkedIn profile URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if request.metadata.allowMultiple {
                Text("Multiple files allowed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            filePickerArea
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var filePickerArea: some View {
        let dashStyle = StrokeStyle(lineWidth: 1.2, dash: [6, 6])
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isDropTargetHighlighted ? Color.accentColor : Color.secondary)
                Text("Drop your file here")
                    .font(.headline)
                Text(request.metadata.allowMultiple ? "You can drop multiple files." : "You can also choose a file from Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Choose File…", action: {
                    onSelectFile()
                })
                Button(skipButtonTitle, action: {
                    onDecline()
                })
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(
            EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargetHighlighted ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDropTargetHighlighted ? Color.accentColor : Color.secondary.opacity(0.2), style: dashStyle)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onSelectFile() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargetHighlighted, perform: handleDrop(providers:))
    }
    private var skipButtonTitle: String {
        if request.metadata.targetKey == "basics.image" {
            return "Skip photo for now"
        }
        return "Skip"
    }
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let supportingProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supportingProviders.isEmpty else { return false }
        Task {
            var collected: [URL] = []
            for provider in supportingProviders {
                if let url = await loadURL(from: provider) {
                    // Validate file type if accepts list is specified
                    if isFileTypeAllowed(url) {
                        collected.append(url)
                        if !request.metadata.allowMultiple { break }
                    }
                }
            }
            if !collected.isEmpty {
                let limited = request.metadata.allowMultiple ? collected : Array(collected.prefix(1))
                await MainActor.run {
                    onDropFiles(limited)
                }
            }
        }
        return true
    }
    private func isFileTypeAllowed(_ url: URL) -> Bool {
        // If no specific types are specified, allow all
        guard !request.metadata.accepts.isEmpty else { return true }
        let fileExtension = url.pathExtension.lowercased()
        return request.metadata.accepts.contains { acceptedType in
            acceptedType.lowercased() == fileExtension
        }
    }
    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
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
}
