//
//  KeywordsDiffView.swift
//  Sprung
//
//  Phase 2 UI for two-phase hierarchical skills review
//  Shows keyword-level changes within a category (add/remove/modify)
//

import SwiftUI
import SwiftData

/// Phase 2 UI: Review keywords within a specific skill category
struct KeywordsDiffView: View {
    @Bindable var viewModel: ResumeReviseViewModel
    @Binding var resume: Resume?
    @Environment(\.modelContext) private var modelContext
    @State private var showCancelConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            if let keywordsRevision = viewModel.currentKeywordsRevision {
                // Keywords diff content
                ScrollView {
                    VStack(spacing: 16) {
                        // Explanation
                        if !keywordsRevision.why.isEmpty {
                            HStack {
                                Image(systemName: "lightbulb")
                                    .foregroundStyle(.yellow)
                                Text(keywordsRevision.why)
                                    .font(.system(.callout, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Side by side diff
                        HStack(alignment: .top, spacing: 20) {
                            // Original keywords
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Original")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                keywordsList(
                                    keywords: keywordsRevision.oldKeywords,
                                    comparison: keywordsRevision.newKeywords,
                                    isOriginal: true
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()

                            // Suggested keywords
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Suggested")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.blue)

                                keywordsList(
                                    keywords: keywordsRevision.newKeywords,
                                    comparison: keywordsRevision.oldKeywords,
                                    isOriginal: false
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 400)
            } else if viewModel.isProcessingRevisions {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Analyzing keywords...")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else {
                // No content
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No keywords to review")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            }

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "tag")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                Text(viewModel.currentKeywordsRevision?.categoryName ?? "Keywords Review")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }

            Text("Review suggested keyword changes for this category")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Phase 2 of 2: Keywords")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())

                Text("Category \(viewModel.currentCategoryIndex + 1) of \(viewModel.pendingCategoryIds.count)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Keywords List

    @ViewBuilder
    private func keywordsList(keywords: [String], comparison: [String], isOriginal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(keywords, id: \.self) { keyword in
                HStack(spacing: 8) {
                    // Status indicator
                    keywordStatusIcon(keyword: keyword, comparison: comparison, isOriginal: isOriginal)

                    Text(keyword)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(keywordTextColor(keyword: keyword, comparison: comparison, isOriginal: isOriginal))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(keywordBackground(keyword: keyword, comparison: comparison, isOriginal: isOriginal))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func keywordStatusIcon(keyword: String, comparison: [String], isOriginal: Bool) -> some View {
        Group {
            if isOriginal {
                // In original list: check if removed
                if !comparison.contains(keyword) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.gray.opacity(0.3))
                }
            } else {
                // In new list: check if added
                if !comparison.contains(keyword) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.gray.opacity(0.3))
                }
            }
        }
        .font(.system(size: 14))
    }

    private func keywordTextColor(keyword: String, comparison: [String], isOriginal: Bool) -> Color {
        if isOriginal && !comparison.contains(keyword) {
            return .red
        } else if !isOriginal && !comparison.contains(keyword) {
            return .green
        }
        return .primary
    }

    private func keywordBackground(keyword: String, comparison: [String], isOriginal: Bool) -> Color {
        if isOriginal && !comparison.contains(keyword) {
            return Color.red.opacity(0.1)
        } else if !isOriginal && !comparison.contains(keyword) {
            return Color.green.opacity(0.1)
        }
        return Color.clear
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Cancel Review") {
                if viewModel.hasUnappliedApprovedChanges() {
                    showCancelConfirmation = true
                } else {
                    viewModel.discardAllAndClose()
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Skip Category") {
                guard let resume = resume else { return }
                viewModel.rejectCurrentKeywordsAndMoveNext(resume: resume)
            }
            .buttonStyle(.bordered)

            Button("Accept Changes") {
                guard let resume = resume else { return }
                viewModel.acceptCurrentKeywordsAndMoveNext(resume: resume, context: modelContext)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.currentKeywordsRevision == nil)
        }
        .padding(20)
        .confirmationDialog(
            "Cancel Review?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply Approved & Close") {
                guard let resume = resume else { return }
                viewModel.applyApprovedChangesAndClose(resume: resume, context: modelContext)
            }
            Button("Discard All", role: .destructive) {
                viewModel.discardAllAndClose()
            }
            Button("Continue Review", role: .cancel) { }
        } message: {
            Text("You have approved changes that haven't been applied yet. Would you like to apply them before closing?")
        }
    }
}

// MARK: - Summary Stats View

struct KeywordsDiffStats: View {
    let oldKeywords: [String]
    let newKeywords: [String]

    private var added: Int {
        newKeywords.filter { !oldKeywords.contains($0) }.count
    }

    private var removed: Int {
        oldKeywords.filter { !newKeywords.contains($0) }.count
    }

    private var kept: Int {
        oldKeywords.filter { newKeywords.contains($0) }.count
    }

    var body: some View {
        HStack(spacing: 16) {
            statBadge(count: kept, label: "Kept", color: .gray)
            statBadge(count: added, label: "Added", color: .green)
            statBadge(count: removed, label: "Removed", color: .red)
        }
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
