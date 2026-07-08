//
//  LinkedInSearchPanel.swift
//  Sprung
//
//  LinkedIn board UI (search controls + results). Owns the one-time risk-consent
//  gate; state and search logic live in LinkedInSearchState.
//

import SwiftUI

struct LinkedInSearchPanel: View {
    @Bindable var state: LinkedInSearchState
    /// True while any board's search is in flight (single-flight across boards).
    let disabled: Bool

    /// Owns the local LinkedIn MCP server's lifecycle (spawn + handshake +
    /// consent flag). Injected from AppDependencies.
    @Environment(LinkedInMCPServerService.self) private var server

    /// One-time risk consent for the LinkedIn board — the first Search presents
    /// LinkedInConsentDialog instead of searching; declining aborts. The flag
    /// itself lives on `server.consentAccepted`.
    @State private var showingConsent = false

    var body: some View {
        VStack(spacing: 0) {
            searchControls
            Divider()
            resultsArea
            Divider()
            footer
        }
        .sheet(isPresented: $showingConsent) {
            // One-time risk consent gates the FIRST LinkedIn call; accepting
            // persists the flag and immediately runs the pending search,
            // declining just dismisses.
            LinkedInConsentDialog(
                onAccept: {
                    server.acceptConsent()
                    showingConsent = false
                    state.search(server: server)
                },
                onDecline: {
                    showingConsent = false
                }
            )
        }
    }

    /// Consent-gated entry point: the first search presents the dialog instead
    /// of searching.
    private func runSearch() {
        guard server.consentAccepted else {
            showingConsent = true
            return
        }
        state.search(server: server)
    }

    // MARK: - Search controls

    private var searchControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Keywords (e.g. staff physicist)", text: $state.keywords)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }

                TextField("Location (optional)", text: $state.location)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { runSearch() }

                Picker("Posted", selection: $state.datePosted) {
                    Text("Any time").tag(LinkedInDatePosted?.none)
                    ForEach(LinkedInDatePosted.allCases) { period in
                        Text(period.displayName).tag(Optional(period))
                    }
                }
                .fixedSize()

                Button("Search") {
                    runSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canSearch || disabled)
            }

            HStack(spacing: 8) {
                ForEach(LinkedInWorkType.allCases) { workType in
                    Toggle(workType.displayName, isOn: Binding(
                        get: { state.workTypes.contains(workType) },
                        set: { isOn in
                            if isOn {
                                state.workTypes.insert(workType)
                            } else {
                                state.workTypes.remove(workType)
                            }
                        }
                    ))
                    .toggleStyle(.button)
                }

                Spacer()

                if state.budget.isExhausted {
                    // Budget rail: the Search button is disabled and the cap is
                    // explained — never silently queued.
                    Label(state.budgetMessage, systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if state.isSearching {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                // LinkedIn searches have two phases (server spawn, then the
                // search itself) — surface which one is running.
                Text(state.phase ?? "Searching LinkedIn…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let errorMessage = state.errorMessage {
            VStack(spacing: 12) {
                Spacer()
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Button("Try Again") {
                    runSearch()
                }
                .buttonStyle(.bordered)
                .disabled(disabled)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if state.results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(emptyStateMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(state.results) { lead in
                LinkedInLeadResultRow(
                    lead: lead,
                    isImported: state.isImported(lead)
                ) {
                    state.importResult(lead)
                }
            }
            .listStyle(.inset)
        }
    }

    private var emptyStateMessage: String {
        state.hasSearched
            ? "No jobs matched your search."
            : "Search LinkedIn through the local MCP server and import results as pipeline leads. Titles land immediately; company and details arrive as each lead enriches."
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // No pagination — one page per user-initiated search (max_pages hard-
            // defaults to 1; a new search is the explicit way to see more).
            if !state.results.isEmpty {
                Text("\(state.results.count) result\(state.results.count == 1 ? "" : "s") • first page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let importSummary = state.importSummary {
                Text(importSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Import All as Leads") {
                state.importAllOnPage()
            }
            .buttonStyle(.bordered)
            .disabled(disabled || state.unimportedOnPage == 0)
        }
        .padding()
    }
}

// MARK: - LinkedIn lead row

/// A LinkedIn search result is deliberately thin: the search payload yields
/// only a stable job id + display title, so the row shows the title and the
/// canonical posting URL. Company/location/description arrive after import,
/// when the lead enriches — the row says so rather than showing blanks.
private struct LinkedInLeadResultRow: View {
    let lead: LinkedInJobLead
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.title)
                    .font(.headline)

                Text(lead.canonicalURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Company and details load after import")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isImported {
                Label("Imported", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Import") {
                    onImport()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let url = URL(string: lead.canonicalURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on LinkedIn", systemImage: "safari")
                }
            }
        }
    }
}
