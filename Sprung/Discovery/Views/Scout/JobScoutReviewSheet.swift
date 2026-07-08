//
//  JobScoutReviewSheet.swift
//  Sprung
//
//  Interactive review of a completed Job Scout run: boards searched,
//  found/duplicate/dismissed counts, run notes as callouts, and each
//  recommendation with its match badges and reasoning. Pending picks carry
//  Import / Dismiss actions (dismiss captures an optional reason that feeds
//  the next run's calibration); nothing enters the pipeline until the user
//  imports it here. Decided picks show their disposition badge. Reads the live
//  report from the service (addressed by run start time) so decisions render
//  as they're made.
//

import SwiftUI

struct JobScoutReviewSheet: View {
    let service: JobScoutService
    let runStartedAt: Date

    @Environment(\.dismiss) private var dismiss
    @State private var dismissingURL: String?
    @State private var dismissReason = ""

    private var report: JobScoutService.ScoutRunReport? {
        service.report(forRunStartedAt: runStartedAt)
    }

    /// Pending picks first (the work to do), then decided picks in report
    /// order (already strongest-verdict-first).
    private var orderedRecommendations: [JobScoutService.ScoutRecommendation] {
        guard let recommendations = report?.recommendations else { return [] }
        return recommendations.enumerated().sorted { lhs, rhs in
            let lPending = lhs.element.disposition == .pending ? 0 : 1
            let rPending = rhs.element.disposition == .pending ? 0 : 1
            return lPending == rPending ? lhs.offset < rhs.offset : lPending < rPending
        }.map(\.element)
    }

    private var pendingCount: Int {
        JobScoutService.pendingCount(in: report)
    }

    private var importedCount: Int {
        report?.recommendations.filter { $0.disposition == .imported }.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report {
                        summarySection(report)
                        if !report.notes.isEmpty {
                            notesSection(report.notes)
                        }
                        recommendationsSection
                    } else {
                        Text("This scout run is no longer available.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 580, idealWidth: 660, minHeight: 480, idealHeight: 640)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scout Review")
                    .font(.headline)
                Text(runStartedAt.formatted(date: .abbreviated, time: .shortened))
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

    private func summarySection(_ report: JobScoutService.ScoutRunReport) -> some View {
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

    private func notesSection(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
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
        }
    }

    // MARK: - Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.subheadline.weight(.semibold))

            if orderedRecommendations.isEmpty {
                Text("The scout made no recommendations this run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orderedRecommendations, id: \.url) { recommendation in
                    recommendationRow(recommendation)
                }
            }
        }
    }

    private func recommendationRow(_ recommendation: JobScoutService.ScoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(.headline)
                    Text(recommendation.company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                dispositionBadge(recommendation.disposition)

                if let url = URL(string: recommendation.url) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Open the posting")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                ScoutMatchBadges(match: recommendation.match)
            }

            Text(recommendation.reasoning)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if recommendation.disposition == .pending {
                actionButtons(for: recommendation)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private func actionButtons(for recommendation: JobScoutService.ScoutRecommendation) -> some View {
        HStack(spacing: 10) {
            Button {
                service.acceptRecommendation(runStartedAt: runStartedAt, url: recommendation.url)
            } label: {
                Label("Import", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                dismissReason = ""
                dismissingURL = recommendation.url
            } label: {
                Label("Dismiss", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .popover(isPresented: Binding(
                get: { dismissingURL == recommendation.url },
                set: { presented in if !presented { dismissingURL = nil } }
            )) {
                dismissPopover(recommendation)
            }

            Spacer()
        }
    }

    private func dismissPopover(_ recommendation: JobScoutService.ScoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dismiss this recommendation?")
                .font(.headline)
            Text("It won't come back in future scout runs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Reason (optional)", text: $dismissReason, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Text("A reason helps the scout calibrate what it surfaces next time.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    dismissingURL = nil
                    dismissReason = ""
                }
                Spacer()
                Button("Dismiss") {
                    let reason = dismissReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    service.dismissRecommendation(
                        runStartedAt: runStartedAt,
                        url: recommendation.url,
                        reason: reason.isEmpty ? nil : reason
                    )
                    dismissingURL = nil
                    dismissReason = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func dispositionBadge(_ disposition: JobScoutService.ScoutRecommendation.Disposition) -> some View {
        let (text, color): (String, Color)
        switch disposition {
        case .pending:
            (text, color) = ("Needs review", .blue)
        case .imported:
            (text, color) = ("Imported", .green)
        case .dismissed:
            (text, color) = ("Dismissed", .secondary)
        case .alreadyInPipeline:
            (text, color) = ("In pipeline", .secondary)
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if pendingCount > 0 {
                Text("\(pendingCount) awaiting your review. Import the ones worth pursuing; dismiss the rest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if importedCount > 0 {
                Text("Imported recommendations are in the pipeline's Identified column at high priority.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing left to review.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }
}
