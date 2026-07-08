//
//  JobSearchView.swift
//  Sprung
//
//  Search an MCP job board (Dice, ZipRecruiter, or LinkedIn via the local
//  MCP server) — or point the agentic Custom Site search at any small
//  "web-fetch friendly" board or careers page — and import results into the
//  pipeline as `.new` leads.
//
//  This is a thin shell: the board picker + single-flight gate. Each board is a
//  self-contained module of an @Observable state model (owned here so an
//  in-flight agent run survives a board switch) and its panel view.
//

import SwiftUI

/// Which job source the view is currently showing. Each board keeps its own
/// search fields, results, pagination cursor, and client/agent state — they're
/// independent search sessions, not tabs over one shared query.
private enum JobBoard: String, CaseIterable, Identifiable, Hashable {
    case dice = "Dice"
    case zipRecruiter = "ZipRecruiter"
    case linkedIn = "LinkedIn"
    case customSite = "Custom Site"

    var id: String { rawValue }
}

struct JobSearchView: View {
    let jobAppStore: JobAppStore

    @State private var selectedBoard: JobBoard = .dice

    // Per-board session state, owned here so a running search (notably the
    // Custom Site agent loop) outlives a board switch.
    @State private var dice: DiceSearchState
    @State private var zip: ZipRecruiterSearchState
    @State private var linkedIn: LinkedInSearchState
    @State private var site: CustomSiteSearchState

    init(jobAppStore: JobAppStore) {
        self.jobAppStore = jobAppStore
        _dice = State(initialValue: DiceSearchState(jobAppStore: jobAppStore))
        _zip = State(initialValue: ZipRecruiterSearchState(jobAppStore: jobAppStore))
        _linkedIn = State(initialValue: LinkedInSearchState(jobAppStore: jobAppStore))
        _site = State(initialValue: CustomSiteSearchState(jobAppStore: jobAppStore))
    }

    /// The board whose search is currently in flight, if any. Searches are
    /// single-flight across boards, so at most one is non-nil.
    private var runningBoard: JobBoard? {
        if dice.isSearching { return .dice }
        if zip.isSearching { return .zipRecruiter }
        if linkedIn.isSearching { return .linkedIn }
        if site.isSearching { return .customSite }
        return nil
    }

    private var anyRunning: Bool { runningBoard != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let running = runningBoard, running != selectedBoard {
                backgroundRunningBanner(running)
                Divider()
            }
            activePanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            // Cooperative cancellation: never leave the agent loop burning
            // tokens for results nobody will see.
            site.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Search Job Boards")
                .font(.headline)

            Picker("Job Board", selection: $selectedBoard) {
                ForEach(JobBoard.allCases) { board in
                    Text(board.rawValue).tag(board)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
        }
        .padding()
    }

    /// Slim strip shown when a search is running on a board other than the one
    /// on screen — keeps the single-flight gate loud (the other boards' Search
    /// buttons are disabled) instead of silently blocking.
    private func backgroundRunningBanner(_ board: JobBoard) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("\(board.rawValue) search running…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Active panel

    @ViewBuilder
    private var activePanel: some View {
        switch selectedBoard {
        case .dice:
            DiceSearchPanel(state: dice, disabled: anyRunning)
        case .zipRecruiter:
            ZipRecruiterSearchPanel(state: zip, disabled: anyRunning)
        case .linkedIn:
            LinkedInSearchPanel(state: linkedIn, disabled: anyRunning)
        case .customSite:
            CustomSiteSearchPanel(state: site, disabled: anyRunning)
        }
    }
}
