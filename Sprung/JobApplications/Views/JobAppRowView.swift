//
//  JobAppRowView.swift
//  Sprung
//
//
import SwiftUI
struct JobAppRowView: View {
    var jobApp: JobApp
    var deleteAction: () -> Void
    var rerunPreprocessingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(jobApp.companyName)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("- \(jobApp.jobPosition)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            // Indicator only for jobs not yet successfully analyzed —
            // pending and failed render distinctly so a failure isn't mistaken
            // for "still working on it".
            if !jobApp.jobDescription.isEmpty {
                switch jobApp.preprocessingStatus {
                case .pending:
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                        .font(.system(size: 9))
                        .help("Awaiting analysis")
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 9))
                        .help("Analysis failed — right-click to retry")
                case .complete:
                    EmptyView()
                }
            }
        }
        .tag(jobApp)
        .padding(.vertical, -2)
        .padding(.horizontal, 4)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .contextMenu {
            if !jobApp.jobDescription.isEmpty {
                Button {
                    rerunPreprocessingAction?()
                } label: {
                    Label(
                        contextMenuLabel,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
            }

            Divider()

            Button(role: .destructive, action: deleteAction) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var contextMenuLabel: String {
        switch jobApp.preprocessingStatus {
        case .pending: return "Analyze Requirements"
        case .complete: return "Re-analyze Requirements"
        case .failed: return "Retry Analysis"
        }
    }
}
