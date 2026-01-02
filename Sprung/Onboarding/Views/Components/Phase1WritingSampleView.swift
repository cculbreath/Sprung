//
//  Phase1WritingSampleView.swift
//  Sprung
//
//  Phase 1 UI component for collecting writing samples.
//  Shows upload drop zone with skip option for users without samples.
//  Drop handling is done by the pane-level drop zone in OnboardingInterviewToolPane.
//
import SwiftUI

/// View that displays writing sample collection UI for Phase 1.
/// Includes skip functionality for users without samples available.
struct Phase1WritingSampleView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onSelectFiles: () -> Void
    let onDoneWithSamples: () -> Void
    let onSkipSamples: () -> Void

    /// Writing samples from the current session (typed ArtifactRecord)
    private var writingSamples: [ArtifactRecord] {
        coordinator.sessionWritingSamples
    }

    /// Check if writing samples collection is already complete
    private var writingSamplesComplete: Bool {
        coordinator.ui.objectiveStatuses[OnboardingObjectiveId.writingSamplesCollected.rawValue] == "completed"
    }

    /// Check if profile is complete (writing sample collection starts after profile)
    private var profileComplete: Bool {
        coordinator.ui.objectiveStatuses[OnboardingObjectiveId.applicantProfileComplete.rawValue] == "completed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if profileComplete && !writingSamplesComplete {
                    // Active writing sample collection
                    headerSection

                    // Upload drop zone (visual hint - drop handled by pane-level)
                    WritingSampleDropZone(
                        onSelectFiles: onSelectFiles
                    )

                    // Paste hint
                    pasteHint

                    // List of collected samples
                    if !writingSamples.isEmpty {
                        collectedSamplesList
                    }

                    // Action buttons
                    actionButtons
                } else if !profileComplete {
                    // Waiting for profile
                    waitingForProfileView
                } else {
                    // Samples complete
                    completedView
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)
                Text("Writing Samples")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !writingSamples.isEmpty {
                    Text("\(writingSamples.count) collected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Share cover letters, emails, or other professional writing to help match your voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var pasteHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("You can also paste text directly in the chat")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(6)
    }

    private var collectedSamplesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collected Samples")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(writingSamples) { sample in
                Phase1WritingSampleRow(sample: sample)
            }
        }
        .padding(.top, 4)
    }

    /// Whether buttons should be disabled (during LLM processing)
    private var buttonsDisabled: Bool {
        coordinator.ui.isProcessing
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            // Done button (prominent when samples exist)
            if !writingSamples.isEmpty {
                Button(action: onDoneWithSamples) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Done with Writing Samples")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(buttonsDisabled)
            }

            // Skip button (always available)
            Button(action: onSkipSamples) {
                HStack {
                    Image(systemName: writingSamples.isEmpty ? "arrow.right.circle" : "arrow.right.circle")
                    Text(writingSamples.isEmpty ? "Skip - I don't have samples handy" : "Continue without more samples")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .foregroundStyle(.secondary)
            .disabled(buttonsDisabled)
        }
        .padding(.top, 8)
    }

    private var waitingForProfileView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("Complete your profile first")
                .font(.subheadline.weight(.medium))

            Text("Writing sample collection will appear here after you've entered your contact information.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var completedView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Writing Samples Complete")
                    .font(.subheadline.weight(.medium))
            }

            if !writingSamples.isEmpty {
                Text("\(writingSamples.count) sample\(writingSamples.count == 1 ? "" : "s") collected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct Phase1WritingSampleRow: View {
    let sample: ArtifactRecord

    private var name: String {
        sample.metadataString("name") ??
        sample.filename.replacingOccurrences(of: ".txt", with: "")
    }

    private var writingType: String {
        sample.metadataString("writing_type") ?? "document"
    }

    private var wordCount: Int {
        if let count = sample.metadataString("word_count"), let num = Int(count) {
            return num
        }
        return sample.extractedContent.split(separator: " ").count
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

/// Visual hint for writing sample drop zone
/// Drop handling is done by the pane-level drop zone in OnboardingInterviewToolPane
private struct WritingSampleDropZone: View {
    let onSelectFiles: () -> Void

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
                .fill(Color(nsColor: .quaternarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .foregroundStyle(Color(nsColor: .separatorColor))
        )
    }
}
