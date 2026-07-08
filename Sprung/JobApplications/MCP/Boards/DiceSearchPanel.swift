//
//  DiceSearchPanel.swift
//  Sprung
//
//  Dice board UI (search controls + results + pagination). State and search
//  logic live in DiceSearchState; this is presentation only.
//

import SwiftUI

struct DiceSearchPanel: View {
    @Bindable var state: DiceSearchState
    /// True while any board's search is in flight (single-flight across boards).
    let disabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchControls
            Divider()
            resultsArea
            Divider()
            footer
        }
    }

    // MARK: - Search controls

    private var searchControls: some View {
        HStack(spacing: 8) {
            TextField("Keywords (e.g. iOS developer)", text: $state.keyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.search(page: 1) }

            TextField("Location (optional)", text: $state.location)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { state.search(page: 1) }

            Picker("Workplace", selection: $state.workplaceType) {
                Text("Any").tag("")
                ForEach(JobMCPImportService.diceWorkplaceTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .fixedSize()

            Button("Search") {
                state.search(page: 1)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.canSearch || disabled)
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
                Text("Searching Dice…")
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
                    state.search(page: state.currentPage)
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
            List(state.results) { result in
                JobSearchResultRow(
                    result: result,
                    isImported: state.isImported(result)
                ) {
                    state.importResult(result)
                }
            }
            .listStyle(.inset)
        }
    }

    private var emptyStateMessage: String {
        state.hasSearched
            ? "No jobs matched your search."
            : "Search Dice and import results as pipeline leads."
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                state.search(page: state.currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(disabled || !state.canGoBack)

            Text(state.pageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                state.search(page: state.currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(disabled || !state.canGoForward)

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

// MARK: - Dice result row

private struct JobSearchResultRow: View {
    let result: DiceJobResult
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title ?? "Untitled")
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(result.companyName ?? "Unknown company")
                    if let locationName = result.jobLocation?.displayName, !locationName.isEmpty {
                        Text("•")
                        Text(locationName)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let summary = result.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    if let employmentType = result.employmentType, !employmentType.isEmpty {
                        JobResultDetailTag(employmentType)
                    }
                    if let workplaceTypes = result.workplaceTypes, !workplaceTypes.isEmpty {
                        JobResultDetailTag(workplaceTypes.joined(separator: ", "))
                    }
                    if let salary = result.salary, !salary.isEmpty {
                        JobResultDetailTag(salary)
                    }
                    if result.easyApply == true {
                        JobResultDetailTag("Easy Apply")
                    }
                    if let postedDate = result.postedDate, !postedDate.isEmpty {
                        Text(JobMCPImportService.displayPostedDate(postedDate))
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
            if let rawURL = result.detailsPageUrl, let url = URL(string: rawURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on Dice", systemImage: "safari")
                }
            }
        }
    }
}
