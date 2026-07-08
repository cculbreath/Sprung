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

    // Inherited from SidebarView; 1.0 when the user hasn't zoomed the list.
    @Environment(\.fontScale) private var fontScale

    /// Row vertical padding tracks the font scale so rows loosen slightly as
    /// the text grows (and tighten when it shrinks). -2 preserves the original
    /// compact look at 1.0.
    private var rowVerticalPadding: CGFloat { -2 + (fontScale - 1) * 4 }

    var body: some View {
        HStack(spacing: 4) {
            Text(jobApp.companyName)
                .scaledFont(size: 11)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("- \(jobApp.jobPosition)")
                .scaledFont(size: 11)
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
                        .scaledFont(size: 9)
                        .help("Awaiting analysis")
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .scaledFont(size: 9)
                        .help("Analysis failed — right-click to retry")
                case .complete:
                    EmptyView()
                }
            }
        }
        .tag(jobApp)
        .padding(.vertical, rowVerticalPadding)
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
