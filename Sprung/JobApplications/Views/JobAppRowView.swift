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
            // Only show indicator for jobs awaiting analysis (not for completed)
            if !jobApp.jobDescription.isEmpty && !jobApp.hasPreprocessingComplete {
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
