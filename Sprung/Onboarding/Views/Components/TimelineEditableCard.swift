import SwiftUI

/// Unified timeline card that can display in collapsed (read-only) or expanded (editable) mode.
/// Combines the visual styling of TimelineCardRow with inline editing capabilities.
struct TimelineEditableCard: View {
    @Binding var entry: TimelineEntryDraft
    let isExpanded: Bool
    let isReordering: Bool
    let canEdit: Bool  // False in browse mode
    let index: Int
    let totalCount: Int
    let onTap: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible) - matches TimelineCardRow styling
            collapsedHeader
                .contentShape(Rectangle())
                .onTapGesture {
                    if canEdit {
                        onTap()
                    }
                }

            // Expanded edit fields (conditional)
            if isExpanded && canEdit {
                Divider()
                    .padding(.vertical, 8)
                editFields
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isExpanded ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Collapsed Header (TimelineCardRow styling)

    private var collapsedHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? "Untitled" : entry.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(entry.title.isEmpty ? .secondary : .primary)

                    Text(entry.organization.isEmpty ? "No organization" : entry.organization)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isReordering && canEdit {
                    reorderButtons
                }

                experienceTypeBadge

                if canEdit && !isReordering {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Location & Date range
            HStack(spacing: 6) {
                if !entry.location.isEmpty {
                    Text(entry.location)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                if !entry.start.isEmpty {
                    Text(formatDate(entry.start))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !entry.start.isEmpty {
                    Text("–")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.end.isEmpty ? "Present" : formatDate(entry.end))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var reorderButtons: some View {
        HStack(spacing: 4) {
            Button {
                onMoveUp()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)

            Button {
                onMoveDown()
            } label: {
                Image(systemName: "arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(index >= totalCount - 1)
        }
    }

    @ViewBuilder
    private var experienceTypeBadge: some View {
        let (color, label) = typeInfo(for: entry.experienceType)

        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    // MARK: - Expanded Edit Fields

    private var editFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Type picker
            HStack {
                Text("Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $entry.experienceType) {
                    ForEach(ExperienceType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Title & Organization
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Job title, degree, etc.", text: $entry.title)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Company, school, etc.", text: $entry.organization)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Location & Dates
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("City, State", text: $entry.location)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM", text: $entry.start)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM or blank", text: $entry.end)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
            }

            // Summary
            VStack(alignment: .leading, spacing: 4) {
                Text("Summary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Brief description (optional)", text: $entry.summary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            // Highlights
            highlightsEditor
        }
        .padding(.top, 4)
    }

    private var highlightsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Highlights")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    entry.highlights.append("")
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(Array(entry.highlights.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        "Highlight",
                        text: Binding(
                            get: { entry.highlights.indices.contains(index) ? entry.highlights[index] : "" },
                            set: { newValue in
                                if entry.highlights.indices.contains(index) {
                                    entry.highlights[index] = newValue
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        if entry.highlights.indices.contains(index) {
                            entry.highlights.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Helpers

    private func typeInfo(for type: ExperienceType) -> (Color, String) {
        switch type {
        case .education: return (.purple, "Education")
        case .volunteer: return (.orange, "Volunteer")
        case .project: return (.green, "Project")
        case .work: return (.blue, "Work")
        }
    }

    private func formatDate(_ dateString: String) -> String {
        // Handle various ISO formats: YYYY, YYYY-MM, YYYY-MM-DD
        let components = dateString.split(separator: "-")
        guard let year = components.first else { return dateString }

        if components.count >= 2, let month = Int(components[1]) {
            let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if month > 0, month < 13 {
                return "\(monthNames[month]) \(year)"
            }
        }

        return String(year)
    }
}
