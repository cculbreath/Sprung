//
//  WritingCorpusCollectionView.swift
//  Sprung
//
//  Phase 3 UI component for collecting writing samples.
//  Displays an upload drop zone and tracks collected samples.
//
import SwiftUI
import SwiftyJSON

/// View that displays writing sample collection UI for Phase 3.
/// Shows a drop zone for uploads and a list of collected writing samples.
struct WritingCorpusCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onDropFiles: ([URL]) -> Void
    let onSelectFiles: () -> Void
    let onDoneWithSamples: () -> Void
    let onEndInterview: () -> Void

    private var writingSamples: [JSON] {
        // Check multiple fields since writing samples can come from different sources:
        // - IngestWritingSampleTool (chat paste): sets source_type = "writing_sample"
        // - File uploads via get_user_upload: sets document_type = "writingSample" or "writing_sample"
        coordinator.ui.artifactRecords.filter { artifact in
            artifact["source_type"].stringValue == "writing_sample" ||
            artifact["document_type"].stringValue == "writingSample" ||
            artifact["document_type"].stringValue == "writing_sample" ||
            artifact["metadata"]["writing_type"].exists()
        }
    }

    /// Check if writing samples collection is complete (based on objective status)
    private var writingSamplesComplete: Bool {
        coordinator.ui.objectiveStatuses["one_writing_sample"] == "completed"
    }

    /// Check if dossier is complete (based on objective status)
    private var dossierComplete: Bool {
        coordinator.ui.objectiveStatuses["dossier_complete"] == "completed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !writingSamplesComplete {
                // Phase 3.1: Writing Sample Collection
                headerSection

                // Upload drop zone for writing samples
                WritingSampleDropZone(
                    onDropFiles: onDropFiles,
                    onSelectFiles: onSelectFiles
                )

                // List of collected samples
                if !writingSamples.isEmpty {
                    collectedSamplesList
                }

                // Simple sample count indicator
                sampleStatusSection

                // "Done with Writing Samples" button
                if !writingSamples.isEmpty {
                    doneWithSamplesButton
                }
            } else {
                // Phase 3.2: Dossier Finalization
                dossierSection
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var doneWithSamplesButton: some View {
        Button(action: onDoneWithSamples) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Done with Writing Samples")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .padding(.top, 8)
    }

    private var dossierSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header for dossier phase
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Dossier Finalization")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if dossierComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text("The assistant is compiling your candidate dossier. Answer any follow-up questions in chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Summary of collected writing samples
            if !writingSamples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(writingSamples.count) writing sample\(writingSamples.count == 1 ? "" : "s") collected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            // "End Interview" button
            endInterviewButton
        }
    }

    private var endInterviewButton: some View {
        Button(action: onEndInterview) {
            HStack {
                Image(systemName: "flag.checkered")
                Text("End Interview")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.regular)
        .padding(.top, 8)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Writing Samples")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(writingSamples.count) collected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Share cover letters, emails, or other professional writing to help calibrate your voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var collectedSamplesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collected Samples")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(writingSamples.indices, id: \.self) { index in
                WritingSampleRow(sample: writingSamples[index])
            }
        }
        .padding(.top, 4)
    }

    private var sampleStatusSection: some View {
        HStack(spacing: 8) {
            let hasAtLeastOne = !writingSamples.isEmpty
            Image(systemName: hasAtLeastOne ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(hasAtLeastOne ? .green : .secondary)
            Text(hasAtLeastOne ? "Writing sample collected" : "No samples yet")
                .font(.caption)
                .foregroundStyle(hasAtLeastOne ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(writingSamples.isEmpty ? Color.clear : Color.green.opacity(0.1))
        .cornerRadius(6)
        .padding(.top, 8)
    }
}

private struct WritingSampleRow: View {
    let sample: JSON

    private var name: String {
        sample["metadata"]["name"].string ??
        sample["filename"].stringValue.replacingOccurrences(of: ".txt", with: "")
    }

    private var writingType: String {
        sample["metadata"]["writing_type"].string ?? "document"
    }

    private var wordCount: Int {
        sample["metadata"]["word_count"].int ??
        (sample["extracted_text"].stringValue.split(separator: " ").count)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text("\(formattedType) • \(wordCount) words")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(6)
    }

    private var iconName: String {
        switch writingType {
        case "cover_letter": return "doc.text.fill"
        case "email": return "envelope.fill"
        case "essay": return "text.alignleft"
        case "proposal": return "doc.plaintext.fill"
        case "report": return "chart.bar.doc.horizontal.fill"
        case "blog_post": return "doc.richtext.fill"
        case "documentation": return "book.fill"
        default: return "doc.fill"
        }
    }

    private var formattedType: String {
        writingType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct WritingSampleDropZone: View {
    let onDropFiles: ([URL]) -> Void
    let onSelectFiles: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Drop writing samples here")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text("PDF, DOCX, TXT, or paste text in chat")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button(action: onSelectFiles) {
                Label("Select Files", systemImage: "folder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .quaternarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                onDropFiles(urls)
            }
        }
    }
}
