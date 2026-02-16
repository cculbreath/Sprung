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
            // Only show indicator for jobs awaiting analysis (not for completed)
            if !jobApp.jobDescription.isEmpty && !jobApp.hasPreprocessingComplete {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
                    .font(.system(size: 9))
                    .help("Awaiting analysis")
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
                        jobApp.hasPreprocessingComplete ? "Re-analyze Requirements" : "Analyze Requirements",
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
}
