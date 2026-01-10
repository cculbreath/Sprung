import SwiftUI

/// Tab view for browsing writing context in the completion review sheet
struct WritingContextBrowserTab: View {
    let coverRefStore: CoverRefStore

    @State private var searchText = ""
    @State private var selectedType: CoverRefType?
    @State private var expandedIds: Set<String> = []

    private var allRefs: [CoverRef] {
        coverRefStore.storedCoverRefs
    }

    private var filteredRefs: [CoverRef] {
        var refs = allRefs

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            refs = refs.filter {
                $0.name.lowercased().contains(search) ||
                $0.content.lowercased().contains(search)
            }
        }

        if let type = selectedType {
            refs = refs.filter { $0.type == type }
        }

        return refs
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if allRefs.isEmpty {
                emptyState
            } else if filteredRefs.isEmpty {
                noMatchesState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRefs) { ref in
                            refRow(ref)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search writing context...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    typeChip(nil, label: "All", count: allRefs.count)
                    typeChip(.writingSample, label: "Writing Samples", count: allRefs.filter { $0.type == .writingSample }.count)
                    typeChip(.backgroundFact, label: "Background Facts", count: allRefs.filter { $0.type == .backgroundFact }.count)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func typeChip(_ type: CoverRefType?, label: String, count: Int) -> some View {
        let isSelected = selectedType == type

        return Button(action: { selectedType = type }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func refRow(_ ref: CoverRef) -> some View {
        let isExpanded = expandedIds.contains(ref.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedIds.remove(ref.id)
                    } else {
                        expandedIds.insert(ref.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: ref.type == .writingSample ? "doc.text" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(ref.type == .writingSample ? .blue : .orange)

                    Text(ref.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Text("\(ref.content.split(separator: " ").count) words")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 12)

                    Text(ref.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Writing Context")
                .font(.title3.weight(.medium))
            Text("Writing samples and background facts will appear here")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Matches")
                .font(.headline)
            Button("Clear Filters") {
                searchText = ""
                selectedType = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
