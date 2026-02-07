//
//  SourcesView.swift
//  Sprung
//
//  Job sources view for tracking job boards and career sites.
//  Displays sources with visit tracking and discovery functionality.
//

import SwiftUI

struct SourcesView: View {
    let coordinator: DiscoveryCoordinator
    @Binding var triggerDiscovery: Bool
    @State private var showingAddSheet = false
    @State private var editingSource: JobSource?
    @State private var selectedCategory: SourceCategory?

    init(coordinator: DiscoveryCoordinator, triggerDiscovery: Binding<Bool> = .constant(false)) {
        self.coordinator = coordinator
        self._triggerDiscovery = triggerDiscovery
    }

    private var isDiscovering: Bool {
        coordinator.sourcesDiscovery.isActive
    }

    private var filteredSources: [JobSource] {
        guard let category = selectedCategory else {
            return coordinator.jobSourceStore.sources
        }
        return coordinator.jobSourceStore.sources.filter { $0.category == category }
    }

    private var filteredDueSources: [JobSource] {
        guard let category = selectedCategory else {
            return coordinator.jobSourceStore.dueSources
        }
        return coordinator.jobSourceStore.dueSources.filter { $0.category == category }
    }

    /// Categories that actually have sources, for the filter bar
    private var availableCategories: [SourceCategory] {
        let used = Set(coordinator.jobSourceStore.sources.map { $0.category })
        return SourceCategory.allCases.filter { used.contains($0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            if coordinator.jobSourceStore.sources.isEmpty {
                Spacer()

                Image(systemName: "signpost.right.and.left.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Job Sources")
                    .font(.title)

                Text("Track job boards, company career pages, and other sources.\nMark when you visit them and track which sources yield results.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)

                // Discovery status display
                if isDiscovering {
                    AnimatedThinkingText(statusMessage: coordinator.sourcesDiscovery.status.message)
                        .padding(.vertical, 8)

                    Button("Cancel") {
                        coordinator.cancelSourcesDiscovery()
                    }
                    .buttonStyle(.bordered)
                } else if case .complete = coordinator.sourcesDiscovery.status {
                    Text(coordinator.sourcesDiscovery.status.message)
                        .font(.callout)
                        .foregroundStyle(.green)
                        .padding(.vertical, 8)
                } else if case .error(let msg) = coordinator.sourcesDiscovery.status {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.vertical, 8)
                }

                if !isDiscovering {
                    HStack(spacing: 12) {
                        Button {
                            coordinator.startSourcesDiscovery()
                        } label: {
                            Text("Discover Sources")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Add Manually") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            } else {
                // Category filter bar
                if availableCategories.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FilterChip(label: "All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(availableCategories, id: \.self) { category in
                                FilterChip(label: category.rawValue, isSelected: selectedCategory == category) {
                                    selectedCategory = selectedCategory == category ? nil : category
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, -12)
                }

                List {
                    Section {
                        ForEach(filteredDueSources) { source in
                            SourceRowView(source: source, store: coordinator.jobSourceStore) {
                                editingSource = source
                            }
                        }
                        .onDelete { indexSet in
                            deleteFromDue(at: indexSet)
                        }
                    } header: {
                        if !filteredDueSources.isEmpty {
                            Text("Due for Visit")
                        }
                    }

                    Section("All Sources") {
                        ForEach(filteredSources) { source in
                            SourceRowView(source: source, store: coordinator.jobSourceStore) {
                                editingSource = source
                            }
                        }
                        .onDelete { indexSet in
                            deleteFromAll(at: indexSet)
                        }
                    }
                }
                .scrollContentBackground(.visible)
                .scrollEdgeEffect()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
        .sheet(isPresented: $showingAddSheet) {
            AddSourceSheet(store: coordinator.jobSourceStore)
        }
        .sheet(item: $editingSource) { source in
            AddSourceSheet(store: coordinator.jobSourceStore, editing: source)
        }
        .onChange(of: triggerDiscovery) { _, newValue in
            if newValue {
                triggerDiscovery = false
                coordinator.startSourcesDiscovery()
            }
        }
    }

    private func openAllDueSources() {
        let dueSources = coordinator.jobSourceStore.dueSources
        let urls = dueSources.compactMap { URL(string: $0.url) }

        guard !urls.isEmpty else { return }

        // Open all URLs in the default browser as tabs
        for url in urls {
            NSWorkspace.shared.open(url)
        }

        // Mark all as visited
        for source in dueSources {
            coordinator.jobSourceStore.markVisited(source)
        }
    }

    private func deleteFromDue(at indexSet: IndexSet) {
        let sources = filteredDueSources
        for index in indexSet {
            coordinator.jobSourceStore.delete(sources[index])
        }
    }

    private func deleteFromAll(at indexSet: IndexSet) {
        let sources = filteredSources
        for index in indexSet {
            coordinator.jobSourceStore.delete(sources[index])
        }
    }
}

struct SourceRowView: View {
    let source: JobSource
    let store: JobSourceStore
    var onEdit: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.headline)
                    if !source.urlValid {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .help("URL validation failed")
                    }
                }
                HStack(spacing: 8) {
                    Text(source.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Every \(source.recommendedCadenceDays)d")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if source.isDue {
                Text("Due")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }

            if let days = source.daysSinceVisit {
                Text("\(days)d ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Visit") {
                store.markVisited(source)
                if let url = URL(string: source.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)

            Button {
                store.delete(source)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .help("Delete source")
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onEdit()
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                if let url = URL(string: source.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }

            Divider()

            Menu("Reminder Frequency") {
                ForEach([1, 2, 3, 5, 7, 14], id: \.self) { days in
                    Button {
                        store.updateCadence(source, days: days)
                    } label: {
                        HStack {
                            Text(days == 1 ? "Daily" : "Every \(days) days")
                            if source.recommendedCadenceDays == days {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                store.delete(source)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Source Sheet

struct AddSourceSheet: View {
    let store: JobSourceStore
    let editing: JobSource?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var category: SourceCategory = .aggregator
    @State private var cadenceDays = 7

    private var isEditing: Bool { editing != nil }

    init(store: JobSourceStore, editing: JobSource? = nil) {
        self.store = store
        self.editing = editing
        if let source = editing {
            _name = State(initialValue: source.name)
            _url = State(initialValue: source.url)
            _category = State(initialValue: source.category)
            _cadenceDays = State(initialValue: source.recommendedCadenceDays)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text(isEditing ? "Edit Job Source" : "Add Job Source")
                    .font(.headline)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    saveSource()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)

                Picker("Category", selection: $category) {
                    ForEach(SourceCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }

                Picker("Reminder Frequency", selection: $cadenceDays) {
                    Text("Daily").tag(1)
                    Text("Every 2 days").tag(2)
                    Text("Every 3 days").tag(3)
                    Text("Every 5 days").tag(5)
                    Text("Every 7 days").tag(7)
                    Text("Every 14 days").tag(14)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 280)
        .onChange(of: category) { _, newCategory in
            if !isEditing {
                cadenceDays = newCategory.defaultCadenceDays
            }
        }
    }

    private func saveSource() {
        if let source = editing {
            source.name = name
            source.url = url
            source.category = category
            source.recommendedCadenceDays = cadenceDays
        } else {
            let source = JobSource(name: name, url: url, category: category)
            source.recommendedCadenceDays = cadenceDays
            source.isLLMGenerated = false
            store.add(source)
        }
        dismiss()
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
