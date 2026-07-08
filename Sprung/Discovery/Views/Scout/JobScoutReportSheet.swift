//
//  JobScoutReportSheet.swift
//  Sprung
//
//  Read-only rendering of a completed Job Scout run: boards searched,
//  found/duplicate counts, run notes (budget caps, auth failures, skipped
//  boards) as callouts, and each recommendation with its reasoning. Reached
//  from the run modal's last-run line and auto-presented by PipelineView
//  when a manually launched run completes.
//

import SwiftUI

struct JobScoutReportSheet: View {
    let report: JobScoutService.ScoutRunReport

    @Environment(\.dismiss) private var dismiss

    private var importedCount: Int {
        report.recommendations.filter(\.imported).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryLine

                    if !report.notes.isEmpty {
                        notesSection
                    }

                    recommendationsSection
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 460, idealHeight: 600)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scout Report")
                    .font(.headline)
                Text(report.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - Summary

    private var summaryLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            if report.boardsSearched.isEmpty {
                Text("No boards were searched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Searched \(report.boardsSearched.joined(separator: ", "))")
                    .font(.callout)
            }
            Text("Found \(report.resultsFound) postings — \(report.duplicatesDropped) already in your pipeline")
                .font(.callout)
                .foregroundStyle(.secondary)
            if report.previouslyDismissedDropped > 0 {
                Text("\(report.previouslyDismissedDropped) posting\(report.previouslyDismissedDropped == 1 ? "" : "s") you dismissed before, filtered out")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                noteCallout(note)
            }
        }
    }

    private func noteCallout(_ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.orange)
            Text(note)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
        )
    }

    // MARK: - Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.subheadline.weight(.semibold))

            if report.recommendations.isEmpty {
                Text("The scout made no recommendations this run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(report.recommendations.enumerated()), id: \.offset) { _, recommendation in
                    recommendationRow(recommendation)
                }
            }
        }
    }

    private func recommendationRow(_ recommendation: JobScoutService.ScoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(.headline)
                    Text(recommendation.company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if recommendation.imported {
                    Text("Imported")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }

                if let url = URL(string: recommendation.url) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Open the posting")
                }
            }

            Text(recommendation.reasoning)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if importedCount > 0 {
                Text("Imported recommendations are already in the pipeline's Identified column at high priority.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }
}
