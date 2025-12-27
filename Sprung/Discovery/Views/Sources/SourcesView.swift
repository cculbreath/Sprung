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

    init(coordinator: DiscoveryCoordinator, triggerDiscovery: Binding<Bool> = .constant(false)) {
        self.coordinator = coordinator
        self._triggerDiscovery = triggerDiscovery
    }

    private var isDiscovering: Bool {
        coordinator.sourcesDiscovery.isActive
    }

    var body: some View {
        VStack(spacing: 20) {
            if coordinator.jobSourceStore.sources.isEmpty {
                Spacer()

                Image(systemName: "link.circle.fill")
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
                List {
                    Section {
                        ForEach(coordinator.jobSourceStore.dueSources) { source in
                            SourceRowView(source: source, store: coordinator.jobSourceStore)
                        }
                        .onDelete { indexSet in
                            deleteFromDue(at: indexSet)
                        }
                    } header: {
                        if !coordinator.jobSourceStore.dueSources.isEmpty {
                            Text("Due for Visit")
                        }
                    }

                    Section("All Sources") {
                        ForEach(coordinator.jobSourceStore.sources) { source in
                            SourceRowView(source: source, store: coordinator.jobSourceStore)
                        }
                        .onDelete { indexSet in
                            deleteFromAll(at: indexSet)
                        }
                    }
                }
                .scrollContentBackground(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Job Sources")
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    // Status message when active
                    if isDiscovering {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(coordinator.sourcesDiscovery.status.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Button {
                            coordinator.cancelSourcesDiscovery()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .help("Cancel discovery")
                    }

                    Button {
                        openAllDueSources()
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help("Open all due sources in browser tabs")
                    .disabled(coordinator.jobSourceStore.dueSources.isEmpty)

                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        coordinator.startSourcesDiscovery()
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .disabled(isDiscovering)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSourceSheet(store: coordinator.jobSourceStore)
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
        let sources = coordinator.jobSourceStore.dueSources
        for index in indexSet {
            coordinator.jobSourceStore.delete(sources[index])
        }
    }

    private func deleteFromAll(at indexSet: IndexSet) {
        let sources = coordinator.jobSourceStore.sources
        for index in indexSet {
            coordinator.jobSourceStore.delete(sources[index])
        }
    }
}

struct SourceRowView: View {
    let source: JobSource
    let store: JobSourceStore
    @State private var showingCadencePopover = false

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
        }
        .padding(.vertical, 4)
        .contextMenu {
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
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var category: SourceCategory = .aggregator
    @State private var cadenceDays = 7

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Add Job Source")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    addSource()
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
            cadenceDays = newCategory.defaultCadenceDays
        }
    }

    private func addSource() {
        let source = JobSource(name: name, url: url, category: category)
        source.recommendedCadenceDays = cadenceDays
        source.isLLMGenerated = false
        store.add(source)
        dismiss()
    }
}
