//
//  EventCoordinator.swift
//  Sprung
//
//  Event bus implementation: publish/subscribe distribution using AsyncStream.
//
import Foundation

// MARK: - EventCoordinator

/// Event bus that manages event distribution using AsyncStream
actor EventCoordinator {
    // Broadcast continuations: each topic has multiple subscriber continuations
    private var subscriberContinuations: [EventTopic: [UUID: AsyncStream<OnboardingEvent>.Continuation]] = [:]

    #if DEBUG
    // Event history for debugging (debug builds only)
    private var eventHistory: [OnboardingEvent] = []
    private let maxHistorySize = 1000

    // Streaming consolidation state
    private var lastStreamingMessageId: UUID?
    private var consolidatedStreamingUpdates = 0
    private var consolidatedStreamingChars = 0

    // Metrics
    private var metrics = EventMetrics()
    #endif

    struct EventMetrics {
        var publishedCount: [EventTopic: Int] = [:]
        var lastPublishTime: [EventTopic: Date] = [:]
    }

    init() {
        // Initialize subscriber dictionaries for each topic
        for topic in EventTopic.allCases {
            subscriberContinuations[topic] = [:]
            #if DEBUG
            metrics.publishedCount[topic] = 0
            #endif
        }
        Logger.info("📡 EventCoordinator initialized with AsyncStream broadcast architecture", category: .ai)
    }

    deinit {
        // Clean up all continuations
        for continuations in subscriberContinuations.values {
            for continuation in continuations.values {
                continuation.finish()
            }
        }
    }

    /// Subscribe to events for a specific topic
    func stream(topic: EventTopic) -> AsyncStream<OnboardingEvent> {
        let subscriberId = UUID()
        let stream = AsyncStream<OnboardingEvent>(bufferingPolicy: .bufferingNewest(50)) { continuation in
            Task { [weak self] in
                await self?.registerSubscriber(subscriberId, continuation: continuation, for: topic)
            }
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.unregisterSubscriber(subscriberId, for: topic)
                }
            }
        }
        Logger.debug("[EventBus] Subscriber \(subscriberId) connected to topic: \(topic.rawValue)", category: .ai)
        return stream
    }

    private func registerSubscriber(_ id: UUID, continuation: AsyncStream<OnboardingEvent>.Continuation, for topic: EventTopic) {
        subscriberContinuations[topic, default: [:]][id] = continuation
    }

    private func unregisterSubscriber(_ id: UUID, for topic: EventTopic) {
        subscriberContinuations[topic]?[id] = nil
    }

    /// Subscribe to all events (for compatibility/debugging)
    func streamAll() -> AsyncStream<OnboardingEvent> {
        let subscriberId = UUID()
        let stream = AsyncStream<OnboardingEvent>(bufferingPolicy: .unbounded) { continuation in
            Task { [weak self] in
                for topic in EventTopic.allCases {
                    await self?.registerSubscriber(subscriberId, continuation: continuation, for: topic)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    for topic in EventTopic.allCases {
                        await self?.unregisterSubscriber(subscriberId, for: topic)
                    }
                }
            }
        }
        Logger.debug("[EventBus] Subscriber \(subscriberId) connected to ALL topics", category: .ai)
        return stream
    }

    /// Publish an event to its appropriate topic
    func publish(_ event: OnboardingEvent) async {
        let topic = event.topic

        #if DEBUG
        // Log the event (debug builds only)
        Logger.debug("[Event] \(event.logDescription)", category: .ai)

        // Update metrics
        metrics.publishedCount[topic, default: 0] += 1
        metrics.lastPublishTime[topic] = Date()

        // Add to history with streaming event consolidation
        addToHistoryWithConsolidation(event)
        #endif

        // Broadcast to ALL subscriber continuations for this topic
        if let continuations = subscriberContinuations[topic] {
            #if DEBUG
            let subscriberCount = continuations.count
            if case .timeline(.uiUpdateNeeded) = event {
                Logger.info("[EventBus] Delivering timeline.uiUpdateNeeded to \(subscriberCount) subscriber(s)", category: .ai)
            }
            #endif
            for continuation in continuations.values {
                continuation.yield(event)
            }
        } else {
            #if DEBUG
            Logger.warning("[EventBus] No subscribers for topic: \(topic)", category: .ai)
            #endif
        }
    }

    #if DEBUG
    /// Add event to history with consolidation of streaming delta events
    private func addToHistoryWithConsolidation(_ event: OnboardingEvent) {
        // Check if this is a streaming message update
        if case .llm(.streamingMessageUpdated(let id, let delta, let statusMessage)) = event {
            if lastStreamingMessageId == id {
                consolidatedStreamingUpdates += 1
                consolidatedStreamingChars += delta.count
                if let lastIndex = eventHistory.lastIndex(where: {
                    if case .llm(.streamingMessageUpdated(let lastId, _, _)) = $0 {
                        return lastId == id
                    }
                    return false
                }) {
                    let consolidatedEvent = OnboardingEvent.llm(.streamingMessageUpdated(
                        id: id,
                        delta: "[\(consolidatedStreamingUpdates) updates, \(consolidatedStreamingChars) chars total]",
                        statusMessage: statusMessage
                    ))
                    eventHistory[lastIndex] = consolidatedEvent
                }
                return
            } else {
                lastStreamingMessageId = id
                consolidatedStreamingUpdates = 1
                consolidatedStreamingChars = delta.count
            }
        } else {
            lastStreamingMessageId = nil
            consolidatedStreamingUpdates = 0
            consolidatedStreamingChars = 0
        }

        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }
    }

    /// Get metrics for monitoring (debug builds only)
    func getMetrics() -> EventMetrics {
        metrics
    }

    /// Get recent event history (debug builds only)
    func getRecentEvents(count: Int = 10) -> [OnboardingEvent] {
        Array(eventHistory.suffix(count))
    }

    /// Clear event history (debug builds only)
    func clearHistory() {
        eventHistory.removeAll()
    }
    #endif
}

// MARK: - OnboardingEventEmitter Protocol

/// Protocol for components that can emit events
protocol OnboardingEventEmitter {
    var eventBus: EventCoordinator { get }
}

extension OnboardingEventEmitter {
    func emit(_ event: OnboardingEvent) async {
        await eventBus.publish(event)
    }
}
