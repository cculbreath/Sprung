//
//  PendingTitleSetRow.swift
//  Sprung
//
//  Row view for a pending (unreviewed) bulk-generated title set with approve/reject actions.
//

import SwiftUI

struct PendingTitleSetRow: View {
    let words: [TitleWord]
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Words display - wrapping allowed
            Text(words.map { $0.text }.joined(separator: " · "))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            HStack(spacing: 12) {
                Spacer()

                Button(action: onReject) {
                    Label("Reject", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
