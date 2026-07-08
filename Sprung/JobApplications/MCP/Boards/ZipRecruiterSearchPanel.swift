//
//  ZipRecruiterSearchPanel.swift
//  Sprung
//
//  ZipRecruiter board UI (search controls + results + offset pagination). State
//  and search logic live in ZipRecruiterSearchState; this is presentation only.
//

import SwiftUI

struct ZipRecruiterSearchPanel: View {
    @Bindable var state: ZipRecruiterSearchState
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
            TextField("Job role (e.g. software engineer)", text: $state.jobRole)
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.search(offset: 0) }

            TextField("Location (optional)", text: $state.location)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { state.search(offset: 0) }

            Picker("Workplace", selection: $state.locationType) {
                Text("Any").tag("")
                ForEach(JobMCPImportService.zipRecruiterLocationTypes, id: \.self) { type in
                    Text(type.capitalized).tag(type)
                }
            }
            .fixedSize()

            Button("Search") {
                state.search(offset: 0)
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
                Text("Searching ZipRecruiter…")
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
                    state.search(offset: state.offset)
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
                ZipRecruiterResultRow(
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
            : "Search ZipRecruiter and import results as pipeline leads."
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                state.search(offset: max(0, state.offset - state.pageSize))
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(disabled || !state.canGoBack)

            Text(state.pageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                state.search(offset: state.offset + state.pageSize)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(disabled || !state.hasMoreResults)

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

// MARK: - ZipRecruiter result row

private struct ZipRecruiterResultRow: View {
    let result: JobMCPImportService.ZipRecruiterJobResult
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title ?? "Untitled")
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(result.company ?? "Unknown company")
                    if let location = result.location, !location.isEmpty {
                        Text("•")
                        Text(location)
                    }
                    if result.isRemote == true {
                        Text("•")
                        Text("Remote")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let benefits = result.benefits, !benefits.isEmpty {
                    Text(benefits)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let jobType = result.jobType, !jobType.isEmpty {
                        JobResultDetailTag(jobType)
                    }
                    if let salaryDisplay = JobMCPImportService.displaySalaryRange(result.salary) {
                        JobResultDetailTag(salaryDisplay)
                    }
                    if let daysAgo = result.daysAgo {
                        Text(JobMCPImportService.displayDaysAgo(daysAgo))
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
            if let rawURL = result.jobRedirectUrl, let url = URL(string: rawURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on ZipRecruiter", systemImage: "safari")
                }
            }
        }
    }
}
