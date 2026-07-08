//
//  DailyTaskGenerator.swift
//  Sprung
//
//  The single daily-task generation path. Every entry point — the coaching
//  session's update_daily_tasks completion tool, the Daily view refresh, and
//  per-category regeneration — funnels through generate(_:). The generator
//  always receives yesterday's tasks + completion state, the user's search
//  preferences, and weekly-goal deltas, and applies explicit carry-over
//  semantics: an open task either rolls forward or is retired with a
//  user-visible reason. Never silently stomped.
//

import Foundation
import SwiftOpenAI

// MARK: - Trigger

/// What initiated task generation. All triggers share the same context and
/// carry-over semantics; they differ only in the directive handed to the model.
enum DailyTaskGenerationTrigger {
    /// Manual refresh from the Daily view (or discovery onboarding).
    case refresh
    /// End of a coaching session; the coach's directive summarizes the conversation.
    case coachingSession(directive: String)
    /// Per-category regenerate with the user's feedback; only tasks in the
    /// category are generated, carried over, or retired.
    case categoryFeedback(category: TaskCategory, feedback: String)
}

// MARK: - Outcome

/// User-visible record of what a generation run did. Rendered in the Daily view
/// so retirements and dropped tasks are never silent.
struct DailyTaskGenerationOutcome: Equatable {
    struct Retirement: Equatable {
        let title: String
        let reason: String
    }

    struct DroppedTask: Equatable {
        let title: String
        let reason: String
    }

    let addedCount: Int
    let carriedOverCount: Int
    let retirements: [Retirement]
    let droppedTasks: [DroppedTask]
    let summary: String

    var hasNotes: Bool {
        !retirements.isEmpty || !droppedTasks.isEmpty || !summary.isEmpty
    }
}

// MARK: - Response DTOs (structured output, camelCase — keys we control)

struct DailyTaskGenerationResponse: Codable {
    let newTasks: [DailyTaskGenerationEntry]
    /// UUIDs (from the candidate list) of open tasks to roll forward unchanged.
    let carryOver: [String]
    let retired: [DailyTaskRetirementEntry]
    /// One or two plain sentences describing today's plan for the user.
    let summary: String
}

struct DailyTaskGenerationEntry: Codable {
    let taskType: String
    let title: String
    let description: String
    let priority: Int
    let estimatedMinutes: Int
    let relatedId: String?
}

struct DailyTaskRetirementEntry: Codable {
    let taskId: String
    let reason: String
}

// MARK: - Generator

@Observable
@MainActor
final class DailyTaskGenerator {
    private let llmFacade: LLMFacade
    private let dailyTaskStore: DailyTaskStore
    private let preferencesStore: SearchPreferencesStore
    private let weeklyGoalStore: WeeklyGoalStore
    private let sessionStore: CoachingSessionStore
    private let contextProvider: DiscoveryContextProviderImpl

    /// Outcome of the most recent generation run, surfaced in the Daily view.
    var lastOutcome: DailyTaskGenerationOutcome?

    init(
        llmFacade: LLMFacade,
        dailyTaskStore: DailyTaskStore,
        preferencesStore: SearchPreferencesStore,
        weeklyGoalStore: WeeklyGoalStore,
        sessionStore: CoachingSessionStore,
        contextProvider: DiscoveryContextProviderImpl
    ) {
        self.llmFacade = llmFacade
        self.dailyTaskStore = dailyTaskStore
        self.preferencesStore = preferencesStore
        self.weeklyGoalStore = weeklyGoalStore
        self.sessionStore = sessionStore
        self.contextProvider = contextProvider
    }

    // MARK: - The single generation entry point

    @discardableResult
    func generate(_ trigger: DailyTaskGenerationTrigger) async throws -> DailyTaskGenerationOutcome {
        let modelId = try ModelConfigResolver.resolve(
            key: DiscoveryAgentService.anthropicModelSettingKey,
            operation: "Daily Task Generation"
        )

        let scope = categoryScope(for: trigger)
        let candidates = carryOverCandidates(scope: scope)
        let userPrompt = await buildUserPrompt(trigger: trigger, candidates: candidates)
        let systemPrompt = try loadPromptTemplate(named: "discovery_generate_daily_tasks")

        // The facade sets maxTokens to the model's full completion headroom
        // (4096 floor), so large schema-bounded responses aren't truncated.
        let response: DailyTaskGenerationResponse = try await llmFacade.executeStructuredWithAnthropicCaching(
            systemContent: [AnthropicSystemBlock(text: systemPrompt)],
            userPrompt: userPrompt,
            modelId: modelId,
            responseType: DailyTaskGenerationResponse.self,
            schema: Self.responseSchema
        )

        let outcome = apply(response, candidates: candidates, scope: scope)
        lastOutcome = outcome
        Logger.info(
            "✅ Daily tasks generated: \(outcome.addedCount) new, \(outcome.carriedOverCount) carried over, "
            + "\(outcome.retirements.count) retired, \(outcome.droppedTasks.count) dropped",
            category: .ai
        )
        return outcome
    }

    // MARK: - Carry-over candidates

    /// A task the model must explicitly carry over or retire.
    private struct Candidate {
        let task: DailyTask
        /// True when the task row belongs to a previous day (roll forward =
        /// clone into today); false for today's rows (roll forward = keep).
        let isFromPreviousDay: Bool
    }

    private func categoryScope(for trigger: DailyTaskGenerationTrigger) -> TaskCategory? {
        if case .categoryFeedback(let category, _) = trigger { return category }
        return nil
    }

    /// Open (uncompleted) LLM-generated tasks from today plus the most recent
    /// prior task day. User-created tasks are context only — never candidates.
    private func carryOverCandidates(scope: TaskCategory?) -> [Candidate] {
        var candidates: [Candidate] = []

        for task in dailyTaskStore.todaysTasks where task.isLLMGenerated && !task.isCompleted {
            candidates.append(Candidate(task: task, isFromPreviousDay: false))
        }
        if let previous = dailyTaskStore.previousTaskDay() {
            for task in previous.tasks where task.isLLMGenerated && !task.isCompleted {
                candidates.append(Candidate(task: task, isFromPreviousDay: true))
            }
        }

        if let scope {
            candidates = candidates.filter { scope.dailyTaskTypes.contains($0.task.taskType) }
        }
        return candidates
    }

    // MARK: - Prompt Assembly

    private func buildUserPrompt(
        trigger: DailyTaskGenerationTrigger,
        candidates: [Candidate]
    ) async -> String {
        var sections: [String] = []

        sections.append("# Task Generation Request\nToday: \(Self.dayFormatter.string(from: Date()))")

        sections.append("## Directive\n\(directiveText(for: trigger))")

        // Carry-over candidates — the model must decide each one.
        if candidates.isEmpty {
            sections.append("## Open Tasks (carry-over candidates)\nNone.")
        } else {
            var lines: [String] = ["## Open Tasks (carry-over candidates)",
                                   "Every task below must appear in either carryOver or retired:"]
            for candidate in candidates {
                let origin = candidate.isFromPreviousDay ? "from \(Self.dayFormatter.string(from: candidate.task.createdAt))" : "from today"
                var line = "- id: \(candidate.task.id.uuidString) | \(candidate.task.taskType.rawValue) | \(candidate.task.title) (\(origin))"
                if let description = candidate.task.taskDescription, !description.isEmpty {
                    line += " — \(description)"
                }
                lines.append(line)
            }
            sections.append(lines.joined(separator: "\n"))
        }

        // What already got done (context, not candidates).
        let completedToday = dailyTaskStore.todaysTasks.filter { $0.isCompleted }
        if !completedToday.isEmpty {
            let lines = completedToday.map { "- [done] \($0.taskType.rawValue): \($0.title)" }
            sections.append("## Completed Today (do not regenerate)\n" + lines.joined(separator: "\n"))
        }
        let manualOpen = dailyTaskStore.todaysTasks.filter { !$0.isLLMGenerated && !$0.isCompleted }
        if !manualOpen.isEmpty {
            let lines = manualOpen.map { "- \($0.taskType.rawValue): \($0.title)" }
            sections.append("## User-Created Open Tasks (do not modify or duplicate)\n" + lines.joined(separator: "\n"))
        }
        if let previous = dailyTaskStore.previousTaskDay() {
            let done = previous.tasks.filter { $0.isCompleted }
            let summaryLine = "Last task day (\(Self.dayFormatter.string(from: previous.date))): "
                + "\(done.count) of \(previous.tasks.count) completed."
            sections.append("## Recent Completion\n" + summaryLine
                + "\nCompletion streak: \(dailyTaskStore.completionStreakDays()) day(s) with at least one task completed.")
        }

        // Search preferences (what onboarding collected).
        let prefs = preferencesStore.current()
        sections.append("""
            ## Search Preferences
            - Target sectors: \(prefs.targetSectors.joined(separator: ", "))
            - Primary location: \(prefs.primaryLocation)
            - Remote acceptable: \(prefs.remoteAcceptable ? "Yes" : "No")
            - Company size preference: \(prefs.companySizePreference.rawValue)
            """)

        // Weekly goal deltas.
        let goal = weeklyGoalStore.currentWeek()
        let appsActual = weeklyGoalStore.applicationsSubmittedThisWeek()
        sections.append("""
            ## Weekly Goal Progress
            - Applications: \(appsActual) of \(goal.applicationTarget)
            - Events attended: \(goal.eventsAttendedActual) of \(goal.eventsAttendedTarget)
            - New contacts: \(goal.newContactsActual) of \(goal.newContactsTarget)
            """)

        // Coaching context from today's session, if one exists.
        if let session = sessionStore.todaysSession(), !session.recommendations.isEmpty {
            let excerpt = String(session.recommendations.prefix(1500))
            sections.append("## Today's Coaching Notes\n\(excerpt)")
        }

        // Pipeline situation (upcoming events, contacts needing attention).
        let situationJSON = await contextProvider.getDailyTaskContext()
        sections.append("## Current Situation (JSON)\n\(situationJSON)")

        if let scope = categoryScope(for: trigger) {
            sections.append("""
                ## Scope Restriction
                Only generate, carry over, or retire tasks in the \(scope.displayName) category.
                Allowed taskType values: \(scope.taskTypes.joined(separator: ", ")).
                """)
        }

        return sections.joined(separator: "\n\n")
    }

    private func directiveText(for trigger: DailyTaskGenerationTrigger) -> String {
        switch trigger {
        case .refresh:
            return "Routine refresh of today's task list. Balance categories against weekly-goal gaps."
        case .coachingSession(let directive):
            return "From today's coaching session: \(directive)"
        case .categoryFeedback(let category, let feedback):
            return "The user wants different \(category.displayName) tasks. Their feedback: \(feedback)"
        }
    }

    // MARK: - Apply

    private func apply(
        _ response: DailyTaskGenerationResponse,
        candidates: [Candidate],
        scope: TaskCategory?
    ) -> DailyTaskGenerationOutcome {
        var candidatesById: [UUID: Candidate] = [:]
        for candidate in candidates {
            candidatesById[candidate.task.id] = candidate
        }

        var retirements: [DailyTaskGenerationOutcome.Retirement] = []
        var dropped: [DailyTaskGenerationOutcome.DroppedTask] = []
        var carriedOverCount = 0
        var decidedIds = Set<UUID>()

        // Retirements: delete today's rows; prior-day rows just don't roll forward.
        for entry in response.retired {
            guard let id = UUID(uuidString: entry.taskId), let candidate = candidatesById[id] else {
                Logger.warning("Task generation retired unknown task id '\(entry.taskId)'", category: .ai)
                continue
            }
            decidedIds.insert(id)
            retirements.append(.init(title: candidate.task.title, reason: entry.reason))
            if !candidate.isFromPreviousDay {
                dailyTaskStore.delete(candidate.task)
            }
        }

        // Carry-overs: keep today's rows; clone prior-day rows into today.
        var carriedTitles = Set<String>()
        var newTasks: [DailyTask] = []
        for idString in response.carryOver {
            guard let id = UUID(uuidString: idString), let candidate = candidatesById[id] else {
                Logger.warning("Task generation carried over unknown task id '\(idString)'", category: .ai)
                continue
            }
            guard !decidedIds.contains(id) else { continue }
            decidedIds.insert(id)
            carriedOverCount += 1
            carriedTitles.insert(candidate.task.title.lowercased())
            if candidate.isFromPreviousDay {
                newTasks.append(rollForward(candidate.task))
            }
        }

        // Undecided candidates default to carry-over — never silently dropped.
        for candidate in candidates where !decidedIds.contains(candidate.task.id) {
            Logger.info("Task '\(candidate.task.title)' not decided by generator — carrying over", category: .ai)
            carriedOverCount += 1
            carriedTitles.insert(candidate.task.title.lowercased())
            if candidate.isFromPreviousDay {
                newTasks.append(rollForward(candidate.task))
            }
        }

        // New tasks: unmapped types are surfaced, not warn-and-dropped.
        var addedCount = 0
        for entry in response.newTasks {
            guard !entry.title.isEmpty else { continue }
            guard carriedTitles.insert(entry.title.lowercased()).inserted else {
                continue  // model re-emitted a carried task; the carried row wins
            }
            guard let taskType = mapTaskType(entry.taskType) else {
                dropped.append(.init(title: entry.title, reason: "Unrecognized task type '\(entry.taskType)'"))
                continue
            }
            if let scope, !scope.dailyTaskTypes.contains(taskType) {
                dropped.append(.init(title: entry.title, reason: "Outside the \(scope.displayName) category"))
                continue
            }

            let task = DailyTask(type: taskType, title: entry.title,
                                 description: entry.description.isEmpty ? nil : entry.description)
            task.priority = entry.priority
            task.estimatedMinutes = entry.estimatedMinutes
            task.isLLMGenerated = true
            assignRelatedId(entry.relatedId, to: task)
            newTasks.append(task)
            addedCount += 1
        }

        dailyTaskStore.addAll(newTasks)

        return DailyTaskGenerationOutcome(
            addedCount: addedCount,
            carriedOverCount: carriedOverCount,
            retirements: retirements,
            droppedTasks: dropped,
            summary: response.summary
        )
    }

    /// Clone a prior-day open task into a fresh row for today.
    private func rollForward(_ task: DailyTask) -> DailyTask {
        let clone = DailyTask(type: task.taskType, title: task.title, description: task.taskDescription)
        clone.priority = task.priority
        clone.estimatedMinutes = task.estimatedMinutes
        clone.isLLMGenerated = true
        clone.relatedJobAppId = task.relatedJobAppId
        clone.relatedContactId = task.relatedContactId
        clone.relatedEventId = task.relatedEventId
        return clone
    }

    /// Map task type string from the wire contract to DailyTaskType.
    private func mapTaskType(_ typeStr: String) -> DailyTaskType? {
        switch typeStr.lowercased() {
        case "gather": return .gatherLeads
        case "customize": return .customizeMaterials
        case "apply": return .submitApplication
        case "follow_up", "followup": return .followUp
        case "networking": return .networking
        case "event_prep", "eventprep": return .eventPrep
        case "debrief": return .eventDebrief
        default: return nil
        }
    }

    private func assignRelatedId(_ relatedIdString: String?, to task: DailyTask) {
        guard let relatedIdString, let relatedId = UUID(uuidString: relatedIdString) else { return }
        switch task.taskType {
        case .gatherLeads:
            break  // gather tasks have no related entity
        case .customizeMaterials, .submitApplication:
            task.relatedJobAppId = relatedId
        case .followUp:
            // Follow-ups come in two flavors: networking follow-ups reference
            // a contact (from the pendingFollowUps context section),
            // application follow-ups reference a job app.
            if contextProvider.isContactId(relatedId) {
                task.relatedContactId = relatedId
            } else {
                task.relatedJobAppId = relatedId
            }
        case .networking:
            task.relatedContactId = relatedId
        case .eventPrep, .eventDebrief:
            task.relatedEventId = relatedId
        }
    }

    // MARK: - Schema (structured output; every object carries additionalProperties: false)

    static let responseSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "newTasks": [
                "type": "array",
                "description": "New tasks to add today. 3-6 for a full refresh; fewer when many tasks carry over.",
                "items": [
                    "type": "object",
                    "description": "A single new task for the user's daily list",
                    "properties": [
                        "taskType": [
                            "type": "string",
                            "description": "The type of task",
                            "enum": ["gather", "customize", "apply", "follow_up", "networking", "event_prep", "debrief"]
                        ],
                        "title": [
                            "type": "string",
                            "description": "Short, actionable title (2-8 words)"
                        ],
                        "description": [
                            "type": "string",
                            "description": "Brief context or details about the task"
                        ],
                        "priority": [
                            "type": "integer",
                            "description": "Priority level: 0 (low), 1 (medium), 2 (high)"
                        ],
                        "estimatedMinutes": [
                            "type": "integer",
                            "description": "Estimated time in minutes to complete the task"
                        ],
                        "relatedId": [
                            "type": ["string", "null"],
                            "description": "UUID of a related job app, event, or contact from the context, otherwise null"
                        ]
                    ],
                    "required": ["taskType", "title", "description", "priority", "estimatedMinutes", "relatedId"],
                    "additionalProperties": false
                ]
            ],
            "carryOver": [
                "type": "array",
                "description": "UUIDs from the candidate list to roll forward into today unchanged",
                "items": ["type": "string"]
            ],
            "retired": [
                "type": "array",
                "description": "Candidates to retire instead of carrying forward — each with an honest, user-visible reason",
                "items": [
                    "type": "object",
                    "description": "One retired task",
                    "properties": [
                        "taskId": [
                            "type": "string",
                            "description": "UUID from the candidate list"
                        ],
                        "reason": [
                            "type": "string",
                            "description": "Why this task no longer belongs on the list (shown to the user)"
                        ]
                    ],
                    "required": ["taskId", "reason"],
                    "additionalProperties": false
                ]
            ],
            "summary": [
                "type": "string",
                "description": "One or two plain sentences describing today's plan. No buzzwords, no cheerleading."
            ]
        ],
        "required": ["newTasks", "carryOver", "retired", "summary"],
        "additionalProperties": false
    ]

    // MARK: - Helpers

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func loadPromptTemplate(named name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            throw DiscoveryAgentError.promptTemplateMissing(name)
        }
        return content
    }
}
