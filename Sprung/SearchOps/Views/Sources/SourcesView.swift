//
//  SourcesView.swift
//  Sprung
//
//  Job sources view for tracking job boards and career sites.
//  Displays sources with visit tracking and discovery functionality.
//

import SwiftUI

struct SourcesView: View {
    let coordinator: SearchOpsCoordinator
    @State private var isDiscovering = false

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

                Button {
                    Task { await discoverSources() }
                } label: {
                    if isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Discover Sources")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDiscovering)

                Spacer()
            } else {
                List {
                    Section {
                        ForEach(coordinator.jobSourceStore.dueSources) { source in
                            SourceRowView(source: source, coordinator: coordinator)
                        }
                    } header: {
                        if !coordinator.jobSourceStore.dueSources.isEmpty {
                            Text("Due for Visit")
                        }
                    }

                    Section("All Sources") {
                        ForEach(coordinator.jobSourceStore.sources) { source in
                            SourceRowView(source: source, coordinator: coordinator)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await discoverSources() }
                        } label: {
                            if isDiscovering {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "plus")
                            }
                        }
                        .disabled(isDiscovering)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Job Sources")
    }

    private func discoverSources() async {
        isDiscovering = true
        defer { isDiscovering = false }

        do {
            try await coordinator.discoverJobSources()
        } catch {
            Logger.error("Failed to discover sources: \(error)", category: .ai)
        }
    }
}

struct SourceRowView: View {
    let source: JobSource
    let coordinator: SearchOpsCoordinator

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.headline)
                Text(source.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                coordinator.visitSource(source)
                if let url = URL(string: source.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
