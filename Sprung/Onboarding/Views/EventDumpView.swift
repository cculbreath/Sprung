//
//  EventDumpView.swift
//  Sprung
//
//  Debug view for inspecting recent onboarding events
//

import SwiftUI

#if DEBUG
struct EventDumpView: View {
    let coordinator: OnboardingInterviewCoordinator

    @State private var events: [String] = []
    @State private var metricsText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Metrics section
                GroupBox {
                    ScrollView {
                        Text(metricsText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                } label: {
                    Text("Event Metrics")
                        .font(.headline)
                }
                .padding()

                // Events section
                GroupBox {
                    if events.isEmpty {
                        ContentUnavailableView {
                            Label("No Events", systemImage: "tray.fill")
                        } description: {
                            Text("Event history is empty")
                        }
                    } else {
                        List {
                            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("#\(events.count - index)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()

                                        Spacer()
                                    }

                                    Text(event)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .listRowSeparator(.visible)
                            }
                        }
                        .listStyle(.plain)
                    }
                } label: {
                    HStack {
                        Text("Recent Events")
                            .font(.headline)

                        Spacer()

                        Text("\(events.count) events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("Event Dump")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Refresh") {
                        loadEvents()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear History") {
                        Task {
                            await coordinator.clearEventHistory()
                            loadEvents()
                        }
                    }
                }
            }
            .task {
                loadEvents()
            }
        }
        .frame(width: 800, height: 600)
    }

    private func loadEvents() {
        Task {
            let recentEvents = await coordinator.getRecentEvents(count: 50)
            events = recentEvents.map { formatEvent($0) }

            let metrics = await coordinator.getEventMetrics()
            metricsText = formatMetrics(metrics)
        }
    }

    private func formatEvent(_ event: OnboardingEvent) -> String {
        // Simple format - just use the enum case name and basic info
        switch event {
        case .processingStateChanged(let processing):
            return "processingStateChanged(\(processing))"
        case .streamingMessageBegan(let id, _, let reasoningExpected):
            return "streamingMessageBegan(id: \(id.uuidString.prefix(8)), reasoningExpected: \(reasoningExpected))"
        case .streamingMessageUpdated(let id, let delta):
            return "streamingMessageUpdated(id: \(id.uuidString.prefix(8)), delta: \(delta.count) chars)"
        case .streamingMessageFinalized(let id, let text):
            return "streamingMessageFinalized(id: \(id.uuidString.prefix(8)), text: \(text.count) chars)"
        case .llmReasoningSummaryDelta(let delta):
            return "llmReasoningSummaryDelta(\(delta.prefix(50))...)"
        case .llmReasoningSummaryComplete(let text):
            return "llmReasoningSummaryComplete(\(text.count) chars)"
        case .toolCallRequested(let call):
            return "toolCallRequested(\(call.name))"
        case .toolCallCompleted(let id, _):
            return "toolCallCompleted(\(id.uuidString.prefix(8)))"
        case .objectiveStatusChanged(let id, let oldStatus, let newStatus, let phase, _, _):
            return "objectiveStatusChanged(\(id): \(oldStatus ?? "nil") → \(newStatus), phase: \(phase))"
        case .phaseTransitionApplied(let phase, let timestamp):
            return "phaseTransitionApplied(\(phase), \(timestamp.formatted()))"
        case .skeletonTimelineReplaced(_, let diff, _):
            if let diff = diff {
                return "skeletonTimelineReplaced(\(diff.summary))"
            } else {
                return "skeletonTimelineReplaced"
            }
        case .artifactRecordPersisted(let record):
            return "artifactRecordPersisted(id: \(record["id"].stringValue))"
        case .knowledgeCardPersisted(let card):
            return "knowledgeCardPersisted(title: \(card["title"].stringValue))"
        default:
            return "\(event)"
        }
    }

    private func formatMetrics(_ metrics: EventCoordinator.EventMetrics) -> String {
        var lines: [String] = []

        lines.append("Published Event Counts by Topic:")
        for topic in EventTopic.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let count = metrics.publishedCount[topic] ?? 0
            let lastTime = metrics.lastPublishTime[topic]?.formatted(.relative(presentation: .numeric)) ?? "never"
            lines.append("  \(topic.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)): \(count) events (last: \(lastTime))")
        }

        return lines.joined(separator: "\n")
    }
}
#endif
