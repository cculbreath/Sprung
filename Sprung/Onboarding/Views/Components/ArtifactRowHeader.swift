import SwiftUI

/// The always-visible collapsed header for an artifact row: file icon, display name,
/// subtitle, status badges, expand chevron, demote button, and delete button.
struct ArtifactRowHeader: View {
    let artifact: ArtifactRecord
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDemote: () -> Void
    let onDelete: () -> Void

    private var hasContent: Bool {
        !artifact.extractedContent.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 10) {
                    fileIcon
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            // Show filename if different from display name (title)
                            if artifact.title != nil && !artifact.filename.isEmpty {
                                Text(artifact.filename)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if let contentType = artifact.contentType {
                                Text(contentType.components(separatedBy: "/").last ?? contentType)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if artifact.sizeInBytes > 0 {
                                Text(formatFileSize(artifact.sizeInBytes))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()

                    // Status indicators
                    if hasContent {
                        if artifact.hasKnowledgeExtraction {
                            // Content extracted AND knowledge extracted
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .help("Content extracted, knowledge extracted")
                        } else if artifact.isWritingSample {
                            // Writing samples don't need knowledge extraction - show success
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .help("Writing sample extracted")
                        } else {
                            // Content extracted but NO knowledge extraction yet
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                                .help("No skills or narrative cards extracted")
                        }
                    }

                    // Graphics extraction status (PDFs only)
                    if artifact.isPDF {
                        if artifact.graphicsExtractionFailed {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(.orange)
                                .font(.caption)
                                .help("Graphics analysis failed: \(artifact.graphicsExtractionError ?? "Unknown error")")
                        } else if artifact.hasGraphicsContent {
                            Image(systemName: "photo.badge.checkmark")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .help("Visual content analyzed")
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Demote button (remove from interview, keep in archive)
            Button(action: onDemote) {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from interview (keep in archive)")

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete permanently")
        }
    }

    @ViewBuilder
    private var fileIcon: some View {
        let icon = iconForContentType(artifact.contentType)
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    private func iconForContentType(_ contentType: String?) -> String {
        guard let contentType else { return "doc" }
        if contentType.contains("pdf") { return "doc.richtext" }
        if contentType.contains("word") || contentType.contains("docx") { return "doc.text" }
        if contentType.contains("image") { return "photo" }
        if contentType.contains("json") { return "curlybraces" }
        if contentType.contains("text") { return "doc.plaintext" }
        if contentType.contains("git") { return "chevron.left.forwardslash.chevron.right" }
        return "doc"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}
