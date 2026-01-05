//
//  DailyTaskGenerator.swift
//  Sprung
//
//  Handles generation and management of daily tasks from coaching sessions.
//  Extracted from CoachingService for single responsibility.
//

import Foundation
import SwiftyJSON

/// Handles generation and management of daily tasks from coaching sessions
@MainActor
struct DailyTaskGenerator {
    private let dailyTaskStore: DailyTaskStore
    private let llmService: DiscoveryLLMService

    init(dailyTaskStore: DailyTaskStore, llmService: DiscoveryLLMService) {
        self.dailyTaskStore = dailyTaskStore
        self.llmService = llmService
    }

    /// Map task type string from prompt to DailyTaskType enum
    func mapTaskType(_ typeStr: String) -> DailyTaskType? {
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

    /// Save parsed daily tasks, clearing any existing LLM-generated tasks for today
    func saveDailyTasks(_ tasks: [DailyTask]) {
        guard !tasks.isEmpty else { return }

        // Clear existing LLM-generated tasks for today
        for existingTask in dailyTaskStore.todaysTasks where existingTask.isLLMGenerated {
            dailyTaskStore.delete(existingTask)
        }

        // Add new tasks
        dailyTaskStore.addMultiple(tasks)

        Logger.info("Coaching: Saved \(tasks.count) daily tasks", category: .ai)
    }

    /// Handle the update_daily_tasks tool call and save tasks
    /// Returns the count of tasks saved
    func handleUpdateDailyTasksToolCall(arguments: String, session: CoachingSession?) -> Int {
        let json = JSON(parseJSON: arguments)
        let tasksArray = json["tasks"].arrayValue

        var tasks: [DailyTask] = []
        for taskJSON in tasksArray {
            let taskTypeStr = taskJSON["task_type"].stringValue
            guard let taskType = mapTaskType(taskTypeStr) else {
                Logger.warning("Coaching: Unknown task type '\(taskTypeStr)'", category: .ai)
                continue
            }

            let title = taskJSON["title"].stringValue
            guard !title.isEmpty else { continue }

            let task = DailyTask()
            task.taskType = taskType
            task.title = title
            task.taskDescription = taskJSON["description"].string
            task.priority = taskJSON["priority"].intValue
            task.estimatedMinutes = taskJSON["estimated_minutes"].int
            task.isLLMGenerated = true

            // Handle related_id if present
            if let relatedIdStr = taskJSON["related_id"].string,
               let relatedId = UUID(uuidString: relatedIdStr) {
                switch taskType {
                case .gatherLeads:
                    task.relatedJobSourceId = relatedId
                case .customizeMaterials, .submitApplication, .followUp:
                    task.relatedJobAppId = relatedId
                case .networking:
                    task.relatedContactId = relatedId
                case .eventPrep, .eventDebrief:
                    task.relatedEventId = relatedId
                }
            }

            tasks.append(task)
        }

        if !tasks.isEmpty {
            saveDailyTasks(tasks)
            session?.generatedTaskCount = tasks.count
            Logger.info("📋 Saved \(tasks.count) daily tasks from coaching", category: .ai)
        } else {
            Logger.warning("No valid tasks found in update_daily_tasks call", category: .ai)
        }

        return tasks.count
    }

    /// Replace tasks for a specific category with new task JSONs
    func replaceTasksForCategory(_ category: TaskCategory, with taskJSONs: [TaskJSON]) {
        // Delete existing tasks for this category (only LLM-generated ones)
        let today = Calendar.current.startOfDay(for: Date())
        let existingTasks = dailyTaskStore.allTasks.filter { task in
            Calendar.current.isDate(task.createdAt, inSameDayAs: today) &&
            category.dailyTaskTypes.contains(task.taskType) &&
            task.isLLMGenerated
        }

        for task in existingTasks {
            dailyTaskStore.delete(task)
        }

        // Add new tasks
        for taskJSON in taskJSONs {
            guard let taskType = mapTaskType(taskJSON.taskType) else { continue }

            let task = DailyTask(type: taskType, title: taskJSON.title, description: taskJSON.description)
            task.priority = taskJSON.priority
            task.estimatedMinutes = taskJSON.estimatedMinutes
            task.relatedJobAppId = taskJSON.relatedId.flatMap { UUID(uuidString: $0) }
            task.isLLMGenerated = true
            dailyTaskStore.add(task)
        }
    }

    /// Build the prompt for task regeneration
    func buildRegenerationPrompt(
        category: TaskCategory,
        feedback: String,
        coachingRecommendations: String,
        activitySummary: String
    ) -> String {
        """
        # Task Regeneration Request

        ## Category
        \(category.displayName) tasks

        ## User Feedback
        The user wants different suggestions because: \(feedback)

        ## Today's Coaching Context
        \(coachingRecommendations)

        ## Activity Summary
        \(activitySummary)

        ## Task Types to Generate
        Only use these task types for \(category.displayName):
        \(category.taskTypes.map { "- \($0)" }.joined(separator: "\n"))

        ## Instructions
        Generate 2-5 new tasks for the \(category.displayName) category that address the user's feedback.
        Be specific and actionable. Consider the coaching context when making suggestions.
        """
    }
}
