import SwiftUI
import SwiftyJSON

/// Row view for displaying an archived artifact with expand/collapse, promote, and delete actions.
struct ArchivedArtifactRow: View {
    let artifact: ArtifactRecord
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onPromote: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 10) {
                        fileIcon
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.displayName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            if let brief = artifact.briefDescription, !brief.isEmpty {
                                Text(brief)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(artifact.filename)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    // Promote button
                    Button(action: onPromote) {
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Add to current interview")

                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete permanently")
                }
                .padding(.leading, 8)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let summary = artifact.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }

                    if !artifact.extractedContent.isEmpty {
                        Text(artifact.extractedContent.prefix(500) + (artifact.extractedContent.count > 500 ? "..." : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private var fileIcon: some View {
        let iconName: String
        let iconColor: Color

        switch artifact.contentType?.lowercased() {
        case let type where type?.contains("pdf") == true:
            iconName = "doc.richtext"
            iconColor = .red
        case let type where type?.contains("word") == true || type?.contains("docx") == true:
            iconName = "doc.text"
            iconColor = .blue
        case let type where type?.contains("image") == true:
            iconName = "photo"
            iconColor = .green
        default:
            if artifact.sourceType == "git_repository" {
                iconName = "chevron.left.forwardslash.chevron.right"
                iconColor = .orange
            } else {
                iconName = "doc"
                iconColor = .gray
            }
        }

        return Image(systemName: iconName)
            .font(.title2)
            .foregroundStyle(iconColor)
    }
}
