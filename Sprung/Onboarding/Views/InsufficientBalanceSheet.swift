//
//  InsufficientBalanceSheet.swift
//  Sprung
//
//  Modal shown when an onboarding LLM request fails because the API balance is
//  exhausted. Lets the user top up and resume the paused work, or cancel it.
//

import AppKit
import SwiftUI

struct InsufficientBalanceSheet: View {
    let info: BudgetPauseInfo
    let onResume: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "creditcard.trianglebadge.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Balance Exhausted")
                        .font(.title2.weight(.semibold))
                    Text("The interview is paused.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(explanation)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let tokens = tokenDetail {
                Text(tokens)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                openTopUpPage()
            } label: {
                Label("Add Credits at \(info.providerName)", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Divider()

            HStack {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text("Cancel Operation")
                }
                .controlSize(.large)

                Spacer()

                Button {
                    onResume()
                } label: {
                    Text("I've Added Credits — Resume")
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
        "Your \(info.providerName) credit balance is too low to complete this request. "
            + "Add credits, then choose Resume to continue exactly where the interview left off — "
            + "the failed request (and any document analysis that didn't finish) will be retried. "
            + "Choose Cancel to stop the current operation; you can top up and try again later."
    }

    private var tokenDetail: String? {
        guard let requested = info.requested, let available = info.available,
              requested > 0 || available > 0 else { return nil }
        return "Requested \(requested.formatted()) tokens · \(available.formatted()) available"
    }

    private func openTopUpPage() {
        guard let url = URL(string: info.topUpURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
