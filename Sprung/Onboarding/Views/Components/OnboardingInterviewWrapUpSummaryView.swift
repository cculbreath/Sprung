import SwiftUI
import SwiftyJSON

struct WrapUpSummaryView: View {
    let artifacts: OnboardingArtifacts
    let schemaIssues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !schemaIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schema Alerts")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(schemaIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }

            if let profile = artifacts.applicantProfile {
                ArtifactSection(title: "Applicant Profile", content: formattedJSON(profile))
            }

            if let timeline = artifacts.skeletonTimeline {
                ArtifactSection(title: "Skeleton Timeline", content: formattedJSON(timeline))
            }

            if !artifacts.artifactRecords.isEmpty {
                let content = artifacts.artifactRecords.enumerated().map { index, artifact in
                    artifactSummary(artifact, index: index + 1)
                }.joined(separator: "\n\n")
                ArtifactSection(title: "Uploaded Documents", content: content)
            }

            if !artifacts.knowledgeCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Knowledge Cards")
                        .font(.headline)
                    ForEach(Array(artifacts.knowledgeCards.enumerated()), id: \.offset) { index, card in
                        KnowledgeCardView(index: index + 1, card: card)
                            .padding(.vertical, 4)
                    }
                }
            }

            if !artifacts.enabledSections.isEmpty {
                ArtifactSection(
                    title: "Enabled Résumé Sections",
                    content: artifacts.enabledSections.sorted().joined(separator: ", ")
                )
            }
        }
    }

    private func formattedJSON(_ json: JSON) -> String {
        json.rawString(options: .prettyPrinted) ?? json.rawString() ?? ""
    }

    private func artifactSummary(_ artifact: JSON, index: Int) -> String {
        let name = artifact["filename"].string ?? "Document \(index)"
        let sizeBytes = artifact["size_bytes"].int ?? 0
        let sizeString: String
        if sizeBytes > 0 {
            sizeString = String(format: "%.1f KB", Double(sizeBytes) / 1024.0)
        } else {
            sizeString = "Size unknown"
        }

        var lines: [String] = []
        lines.append("\(index). \(name) — \(sizeString)")
        if let artifactId = artifact["id"].string, !artifactId.isEmpty {
            lines.append("   artifact_id: \(artifactId)")
        }
        if let sha = artifact["sha256"].string, !sha.isEmpty {
            lines.append("   SHA256: \(sha)")
        }
        if let metadata = artifact["metadata"].dictionary {
            if let format = metadata["source_format"]?.string {
                lines.append("   Format: \(format)")
            }
            if let purpose = metadata["purpose"]?.string {
                lines.append("   Purpose: \(purpose)")
            }
            if let characters = metadata["character_count"]?.int {
                lines.append("   Characters captured: \(characters)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct ArtifactSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ScrollView {
                Text(content.isEmpty ? "—" : content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct KnowledgeCardView: View {
    let index: Int
    let card: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(index) \(card["title"].stringValue)")
                .font(.headline)
            if let summary = card["summary"].string {
                Text(summary)
                    .font(.body)
            }
            if let source = card["source"].string, !source.isEmpty {
                Label(source, systemImage: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            let metrics = card["metrics"].arrayValue.compactMap { $0.string }
            if !metrics.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metrics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(metrics, id: \.self) { metric in
                        Text("• \(metric)")
                            .font(.caption)
                    }
                }
            }
            let skills = card["skills"].arrayValue.compactMap { $0.string }
            if !skills.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(skills.joined(separator: ", "))
                        .font(.caption)
                }
            }
        }
    }
}

private struct FactLedgerListView: View {
    let entries: [JSON]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fact Ledger")
                .font(.headline)
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry["statement"].stringValue)
                        .font(.subheadline)
                    if let evidence = entry["evidence"].string {
                        Text(evidence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct StyleProfileView: View {
    let profile: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style Profile")
                .font(.headline)
            Text(formattedJSON(profile))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func formattedJSON(_ json: JSON) -> String {
        json.rawString(options: .prettyPrinted) ?? json.rawString() ?? ""
    }
}

private struct WritingSamplesListView: View {
    let samples: [JSON]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Writing Samples")
                .font(.headline)
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample["title"].string ?? sample["name"].string ?? "Sample #\(index + 1)")
                        .font(.subheadline)
                        .bold()
                    if let summary = sample["summary"].string {
                        Text(summary)
                            .font(.caption)
                    }
                    let tone = sample["tone"].string ?? "—"
                    let words = sample["word_count"].int ?? 0
                    let avg = sample["avg_sentence_len"].double ?? 0
                    let active = sample["active_voice_ratio"].double ?? 0
                    let quant = sample["quant_density_per_100w"].double ?? 0

                    Text("Tone: \(tone) • \(words) words • Avg sentence: \(String(format: "%.1f", avg)) words")
                        .font(.caption)
                    Text("Active voice: \(String(format: "%.0f%%", active * 100)) • Quant density: \(String(format: "%.2f", quant)) per 100 words")
                        .font(.caption)

                    let notable = sample["notable_phrases"].arrayValue.compactMap { $0.string }
                    if !notable.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notable phrases")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(notable.prefix(3), id: \.self) { phrase in
                                Text("• \(phrase)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
