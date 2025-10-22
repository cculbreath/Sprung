import SwiftUI

struct UploadRequestCard: View {
    let request: OnboardingUploadRequest
    let onSelectFile: () -> Void
    let onProvideLink: (URL) -> Void
    let onDecline: () -> Void

    @State private var linkText: String = ""
    @State private var linkError: String?

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

            if request.kind == .linkedIn {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("https://www.linkedin.com/in/…", text: $linkText)
                        .textFieldStyle(.roundedBorder)
                    if let error = linkError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Submit Link") {
                            submitLink()
                        }
                        Button("Skip") {
                            onDecline()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button("Choose File…") {
                        onSelectFile()
                    }
                    Button("Skip") {
                        onDecline()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submitLink() {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            linkError = "Please provide a valid LinkedIn URL."
            return
        }
        linkError = nil
        onProvideLink(url)
        linkText = ""
    }
}
