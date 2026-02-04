//
//  SourcesModuleView.swift
//  Sprung
//
//  Job Sources module wrapper.
//

import AppKit
import SwiftUI

/// Job Sources module - wraps existing SourcesView
struct SourcesModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @State private var triggerDiscovery: Bool = false

    private var isDiscovering: Bool {
        coordinator.sourcesDiscovery.isActive
    }

    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Job Sources",
                subtitle: "Find job boards and company pages tailored to your field",
                actions: {
                    AnyView(
                        HStack(spacing: 8) {
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
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                                .help("Cancel discovery")
                            }

                            Button {
                                openAllDueSources()
                            } label: {
                                Label("Open Due", systemImage: "safari")
                            }
                            .help("Open all due sources in browser tabs")
                            .disabled(coordinator.jobSourceStore.dueSources.isEmpty)

                            Button {
                                showingAddSheet = true
                            } label: {
                                Label("Add", systemImage: "plus")
                            }

                            Button {
                                coordinator.startSourcesDiscovery()
                            } label: {
                                Label("Discover", systemImage: "sparkles")
                            }
                            .disabled(isDiscovering)
                        }
                    )
                }
            )

            // Existing SourcesView
            SourcesView(
                coordinator: coordinator,
                triggerDiscovery: $triggerDiscovery
            )
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSourceSheet(store: coordinator.jobSourceStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerSourceDiscovery)) { _ in
            triggerDiscovery = true
        }
    }

    private func openAllDueSources() {
        for source in coordinator.jobSourceStore.dueSources {
            if let url = URL(string: source.url) {
                NSWorkspace.shared.open(url)
            }
        }
        for source in coordinator.jobSourceStore.dueSources {
            coordinator.jobSourceStore.markVisited(source)
        }
    }
}
