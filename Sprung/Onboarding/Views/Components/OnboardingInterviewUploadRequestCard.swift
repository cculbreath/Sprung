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
        VStack(spacing: 12) {
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
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .dropZoneStyle(isHighlighted: isDropTargetHighlighted)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onSelectFile() }
        .onDrop(of: DropZoneHandler.acceptedDropTypes, isTargeted: $isDropTargetHighlighted) { providers in
            DropZoneHandler.handleDrop(providers: providers) { urls in
                let filtered = filterByAcceptedTypes(urls)
                guard !filtered.isEmpty else { return }
                let limited = request.metadata.allowMultiple ? filtered : Array(filtered.prefix(1))
                onDropFiles(limited)
            }
            return true
        }
    }

    private var skipButtonTitle: String {
        if request.metadata.targetKey == "basics.image" {
            return "Skip photo for now"
        }
        return "Skip"
    }

    /// Filter URLs by the request's accepted file types
    private func filterByAcceptedTypes(_ urls: [URL]) -> [URL] {
        // If no specific types are specified, allow all that pass DropZoneHandler validation
        guard !request.metadata.accepts.isEmpty else { return urls }

        return urls.filter { url in
            let fileExtension = url.pathExtension.lowercased()
            return request.metadata.accepts.contains { acceptedType in
                acceptedType.lowercased() == fileExtension
            }
        }
    }
}
