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
        HStack {
            Text("\(jobApp.companyName): \(jobApp.jobPosition)")
            Spacer()
            // Show preprocessing status indicator
            if jobApp.hasPreprocessingComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .help("Requirements analyzed")
            } else if !jobApp.jobDescription.isEmpty {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help("Awaiting analysis")
            }
        }
        .tag(jobApp)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
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
