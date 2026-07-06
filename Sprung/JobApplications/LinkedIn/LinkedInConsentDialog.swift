//
//  LinkedInConsentDialog.swift
//  Sprung
//
//  One-time risk-consent sheet shown before the first LinkedIn search.
//  Pure presentation: the presenting view persists the consent flag
//  (UserDefaults key `LinkedInMCPServerService.consentDefaultsKey`) in
//  `onAccept` and dismisses in both callbacks — accepting enables the board,
//  declining leaves it gated.
//

import SwiftUI

struct LinkedInConsentDialog: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.yellow)
                Text("Search LinkedIn with your own account?")
                    .font(.title3)
                    .bold()
            }

            VStack(alignment: .leading, spacing: 12) {
                consentRow(
                    symbol: "hand.raised",
                    text: "LinkedIn's User Agreement prohibits automated access. "
                        + "Accounts that use automated tools can be restricted or banned. "
                        + "There is no guarantee of account safety."
                )
                consentRow(
                    symbol: "person.crop.circle.badge.checkmark",
                    text: "Searches run as your LinkedIn session, imported automatically "
                        + "from the browser on this Mac where you're signed in to linkedin.com. "
                        + "macOS may show a one-time keychain prompt during the import."
                )
                consentRow(
                    symbol: "magnifyingglass",
                    text: "Sprung only ever calls job search and job details — "
                        + "never messaging, connections, or your profile."
                )
                consentRow(
                    symbol: "tortoise",
                    text: "Keep the volume human-paced: specific searches, one page "
                        + "at a time. Avoid large sweeps."
                )
            }

            HStack {
                Spacer()
                Button("Not Now") {
                    onDecline()
                }
                .keyboardShortcut(.cancelAction)
                Button("I Understand — Enable LinkedIn Search") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func consentRow(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
