//
//  CustomSiteSearchPanel.swift
//  Sprung
//
//  Custom Site board UI (URL + guidance input, streaming agent progress,
//  page-verified results). State and agent orchestration live in
//  CustomSiteSearchState; this is presentation only.
//

import SwiftUI

struct CustomSiteSearchPanel: View {
    @Bindable var state: CustomSiteSearchState
    /// True while any board's search is in flight (single-flight across boards).
    let disabled: Bool

    /// Supplies the LLMFacade the Custom Site agent loop runs on. Present in both
    /// the main and Discovery windows' environments.
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(spacing: 0) {
            searchControls
            Divider()
            resultsArea
            Divider()
            footer
        }
    }

    private func runSearch() {
        state.search(llmFacade: appEnvironment.llmFacade)
    }

    // MARK: - Search controls

    private var searchControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Site URL (e.g. austinjobs.com or a company careers page)", text: $state.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }

                Button("Search") {
                    runSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canSearch || disabled)
                .help("An AI agent browses the site with web search + page fetches and submits only page-verified postings")
            }

            TextField("Keywords or guidance (optional, e.g. \"embedded firmware roles, on-site\")", text: $state.guidance)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runSearch() }
        }
        .padding()
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if state.isSearching {
            siteSearchProgress
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
            if state.hasSearched, let emptyReason = state.emptyReason {
                // The agent submitted nothing and said why — an honest failure
                // the user must see, never a quiet "no results" success.
                VStack(spacing: 12) {
                    Spacer()
                    Label(emptyReason, systemImage: "exclamationmark.triangle.fill")
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
            } else {
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
            }
        } else {
            List(state.results) { listing in
                SiteListingResultRow(
                    listing: listing,
                    isImported: state.isImported(listing)
                ) {
                    state.importResult(listing)
                }
            }
            .listStyle(.inset)
        }
    }

    private var emptyStateMessage: String {
        state.hasSearched
            ? "The agent found no matching postings on the site."
            : "Point the agent at a small job board or company careers page. It browses the site, verifies each posting's page, and imports matches as pipeline leads."
    }

    /// Live agent activity while a Custom Site search runs: spinner, the
    /// streaming per-turn progress lines, and a Cancel affordance.
    private var siteSearchProgress: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Agent searching \(state.searchedHost)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    state.cancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(state.progressLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .onChange(of: state.progressLines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // No pagination — the agent submits one verified list per run.
            if !state.results.isEmpty {
                Text("\(state.results.count) page-verified posting\(state.results.count == 1 ? "" : "s")")
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

// MARK: - Custom Site listing row

private struct SiteListingResultRow: View {
    let listing: SiteJobListing
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(listing.company)
                    if let location = listing.location, !location.isEmpty {
                        Text("•")
                        Text(location)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !listing.summary.isEmpty {
                    Text(listing.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    if let salary = listing.salary, !salary.isEmpty {
                        JobResultDetailTag(salary)
                    }
                    if let postedDate = listing.postedDate, !postedDate.isEmpty {
                        Text(postedDate)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
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
            if let url = URL(string: listing.url) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open Posting", systemImage: "safari")
                }
            }
        }
    }
}
