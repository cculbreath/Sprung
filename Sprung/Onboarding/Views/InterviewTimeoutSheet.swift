//
//  InterviewTimeoutSheet.swift
//  Sprung
//
//  Modal shown when a document's AI analysis times out (a large PDF chunk, or a
//  pass that stalled mid-stream). Lets the user keep waiting (retry the same
//  analysis) or abort (keep the extracted text, skip AI analysis — re-uploadable).
//
//  Default action is Keep Waiting: large-document analysis is slow but usually
//  completes on a retry, and the extracted text is never lost either way.
//

import SwiftUI

struct InterviewTimeoutSheet: View {
    let info: TimeoutPauseInfo
    let onKeepWaiting: () -> Void
    let onAbort: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Document Analysis Is Taking Too Long")
                        .font(.title2.weight(.semibold))
                    Text(info.filename)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(explanation)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Button(role: .cancel) {
                    onAbort()
                } label: {
                    Text("Skip AI Analysis")
                }
                .controlSize(.large)

                Spacer()

                Button {
                    onKeepWaiting()
                } label: {
                    Text("Keep Waiting")
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 460)
        .interactiveDismissDisabled(true)
    }

    private var explanation: String {
        "Analyzing \(info.filename) is taking longer than expected — large documents can be slow. "
            + "Choose Keep Waiting to retry the analysis (it resumes from where it left off). "
            + "Choose Skip AI Analysis to keep the extracted text and continue without knowledge cards — "
            + "you can re-upload this document later to try again."
    }
}
