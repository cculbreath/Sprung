import SwiftUI

/// Minimal editor for skeleton timeline entries (work + education + volunteer + project).
/// Preserves `experienceType` so education entries don't get coerced into work.
struct TimelineEntrySectionView: View {
    @Binding var entries: [TimelineEntryDraft]
    let onChange: () -> Void

    @State private var isReordering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array($entries.enumerated()), id: \.element.id) { index, $entry in
                        entryRow($entry, index: index)
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .onChange(of: entries) { _, _ in
            onChange()
        }
    }

    private var header: some View {
        HStack {
            Text("Timeline Entries")
                .font(.headline)
            Spacer()
            Button(isReordering ? "Done Reordering" : "Reorder") {
                isReordering.toggle()
            }
            .buttonStyle(.bordered)
            Button("Add") {
                withAnimation {
                    entries.append(TimelineEntryDraft())
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func entryRow(_ entry: Binding<TimelineEntryDraft>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Type", selection: entry.experienceType) {
                    ForEach(ExperienceType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                if isReordering {
                    HStack(spacing: 6) {
                        Button {
                            moveUp(index: index)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            moveDown(index: index)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index >= entries.count - 1)
                    }
                }

                Button(role: .destructive) {
                    deleteIndex(index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)

                Text(entry.wrappedValue.id.prefix(8))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TextField("Title", text: entry.title)
                TextField("Organization", text: entry.organization)
            }

            HStack(spacing: 12) {
                TextField("Location", text: entry.location)
                TextField("Start", text: entry.start)
                    .frame(maxWidth: 160)
                TextField("End", text: entry.end)
                    .frame(maxWidth: 160)
            }

            TextField("Summary (optional)", text: entry.summary, axis: .vertical)
                .lineLimit(2...6)

            highlightsEditor(entry)
        }
    }

    private func highlightsEditor(_ entry: Binding<TimelineEntryDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Highlights (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Highlight") {
                    var next = entry.wrappedValue
                    next.highlights.append("")
                    entry.wrappedValue = next
                }
                .buttonStyle(.bordered)
            }

            ForEach(Array(entry.wrappedValue.highlights.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        "Highlight",
                        text: Binding(
                            get: { entry.wrappedValue.highlights.indices.contains(index) ? entry.wrappedValue.highlights[index] : "" },
                            set: { newValue in
                                var next = entry.wrappedValue
                                if next.highlights.indices.contains(index) {
                                    next.highlights[index] = newValue
                                }
                                entry.wrappedValue = next
                            }
                        )
                    )
                    Button(role: .destructive) {
                        var next = entry.wrappedValue
                        if next.highlights.indices.contains(index) {
                            next.highlights.remove(at: index)
                        }
                        entry.wrappedValue = next
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func deleteIndex(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        withAnimation {
            _ = entries.remove(at: index)
        }
    }

    private func moveUp(index: Int) {
        guard index > 0, entries.indices.contains(index) else { return }
        withAnimation {
            entries.swapAt(index, index - 1)
        }
    }

    private func moveDown(index: Int) {
        guard entries.indices.contains(index), index < entries.count - 1 else { return }
        withAnimation {
            entries.swapAt(index, index + 1)
        }
    }
}
