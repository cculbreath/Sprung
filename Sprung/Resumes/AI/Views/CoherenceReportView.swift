//
//  CoherenceReportView.swift
//  Sprung
//
//  Presents the coherence report after the post-assembly coherence pass.
//  Shows a clean success state when no issues are found, or a scannable
//  list of issue cards with dismiss/fix actions when issues exist.
//

import SwiftUI

// MARK: - Coherence Report View

struct CoherenceReportView: View {
    let report: CoherenceReport
    let onDismissAll: () -> Void
    let onFixIssue: (CoherenceIssue) -> Void
    let onFixAll: ([CoherenceIssue]) -> Void
    let onDone: () -> Void

    @State private var dismissedIssueIds: Set<UUID> = []

    /// Issues that haven't been dismissed by the user.
    private var activeIssues: [CoherenceIssue] {
        report.issues.filter { !dismissedIssueIds.contains($0.id) }
    }

    private var highCount: Int {
        activeIssues.filter { $0.severity == "high" }.count
    }

    private var mediumCount: Int {
        activeIssues.filter { $0.severity == "medium" }.count
    }

    private var lowCount: Int {
        activeIssues.filter { $0.severity == "low" }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            if report.overallCoherence == .good && activeIssues.isEmpty {
                successView
            } else {
                // Issue list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(activeIssues) { issue in
                            CoherenceIssueCard(
                                issue: issue,
                                onDismiss: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dismissedIssueIds.insert(issue.id)
                                    }
                                },
                                onFix: {
                                    onFixIssue(issue)
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dismissedIssueIds.insert(issue.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Footer
            footerView
        }
        .frame(minWidth: 600, idealWidth: 750, maxWidth: 900)
        .frame(minHeight: 400, idealHeight: 550, maxHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(headerColor)

                Text("Coherence Check")
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                Spacer()

                coherenceBadge
            }

            // Summary text
            if !report.summary.isEmpty {
                Text(report.summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var headerColor: Color {
        switch report.overallCoherence {
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        }
    }

    private var coherenceBadge: some View {
        let (text, color): (String, Color) = {
            switch report.overallCoherence {
            case .good: return ("Good", .green)
            case .fair: return ("Fair", .orange)
            case .poor: return ("Needs Work", .red)
            }
        }()

        return Text(text)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Success State

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("No Coherence Issues Found")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            Text("Your resume is internally consistent and well-aligned.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            // Issue summary counts
            if !activeIssues.isEmpty {
                issueSummaryLabel
            }

            Spacer()

            if !activeIssues.isEmpty {
                Button("Dismiss All") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dismissedIssueIds.formUnion(activeIssues.map(\.id))
                    }
                    onDismissAll()
                }
                .buttonStyle(.bordered)

                Button("Fix All") {
                    let issuesToFix = activeIssues
                    withAnimation(.easeOut(duration: 0.2)) {
                        dismissedIssueIds.formUnion(issuesToFix.map(\.id))
                    }
                    onFixAll(issuesToFix)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.blue)
            }

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private var issueSummaryLabel: some View {
        let parts: [String] = [
            highCount > 0 ? "\(highCount) high" : nil,
            mediumCount > 0 ? "\(mediumCount) medium" : nil,
            lowCount > 0 ? "\(lowCount) low" : nil,
        ].compactMap { $0 }

        return Text("\(activeIssues.count) issues: \(parts.joined(separator: ", "))")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Issue Card

struct CoherenceIssueCard: View {
    let issue: CoherenceIssue
    let onDismiss: () -> Void
    let onFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category badge + severity
            HStack(spacing: 8) {
                Text(formattedCategory)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(severityColor.opacity(0.15))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())

                Spacer()
            }

            // Description
            Text(issue.description)
                .font(.system(.callout, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Locations
            if !issue.locations.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(issue.locations.joined(separator: ", "))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Suggestion
            if !issue.suggestion.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)

                    Text(issue.suggestion)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(8)
                .background(Color.yellow.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    onDismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .foregroundStyle(.secondary)

                Button {
                    onFix()
                } label: {
                    Label("Fix", systemImage: "wrench")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .foregroundStyle(.blue)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(severityColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var severityColor: Color {
        switch issue.severity.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .gray
        }
    }

    private var formattedCategory: String {
        // Convert camelCase/snake_case to Title Case
        issue.category
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}
