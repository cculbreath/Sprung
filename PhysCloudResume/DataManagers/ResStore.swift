//
//  ResStore.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

//
//  swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/30/24.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class ResStore: SwiftDataStore {
    // MARK: - Properties

    unowned let modelContext: ModelContext

    // Computed collection that always reflects current SwiftData contents.
    var resumes: [Resume] {
        (try? modelContext.fetch(FetchDescriptor<Resume>())) ?? []
    }

    // MARK: - Initialiser

    init(context: ModelContext) {
        modelContext = context
    }

    @discardableResult
    func addResume(res: Resume, to jobApp: JobApp) -> Resume {
        jobApp.addResume(res)
        res.model!.resumes.append(res)
        modelContext.insert(res)
        saveContext()

        return res
    }

    @discardableResult
    func create(jobApp: JobApp, sources: [ResRef], model: ResModel) -> Resume? {
        // ModelContext is guaranteed to exist
        let modelContext = self.modelContext

        let resume = Resume(jobApp: jobApp, enabledSources: sources, model: model)

        if jobApp.selectedRes == nil {
            jobApp.selectedRes = resume
        }

        guard let builder = JsonToTree(resume: resume, rawJson: model.json) else {
            return nil
        }
        resume.rootNode = builder.buildTree()
//                Logger.debug(builder.json)

        // Persist new resume (and trigger observers)
        jobApp.addResume(resume)
        modelContext.insert(resume)
        saveContext()

        resume.debounceExport()

        return resume
    }

    func createDuplicate(originalResume: Resume, context: ModelContext) -> Resume? {
        // Step 1: Create a new Resume instance
        if let jobAppo = originalResume.jobApp {
            let newResume = Resume(jobApp: jobAppo, enabledSources: originalResume.enabledSources, model: originalResume.model!)
            // Indexes of copied nodes will be assigned sequentially within their new parent.

            // Step 2: Deep copy the root node and its children
            if let rootNode = originalResume.rootNode {
                let rootNodeCopy = copyTreeNode(node: rootNode, newResume: newResume)
                newResume.rootNode = rootNodeCopy
            }

            // Step 3: Save the new resume to the context
            context.insert(newResume)

            do {
                try context.save()
            } catch {
                return nil
            }

            return newResume
        } else { return nil }
    }

    // Async version of createDuplicate that can be awaited
    func createDuplicateAsync(originalResume: Resume, context: ModelContext) async -> Resume? {
        // Step 1: Create a new Resume instance
        if let jobAppo = originalResume.jobApp {
            let newResume = Resume(jobApp: jobAppo, enabledSources: originalResume.enabledSources, model: originalResume.model!)
            // Indexes of copied nodes will be assigned sequentially within their new parent.

            // Step 2: Deep copy the root node and its children
            if let rootNode = originalResume.rootNode {
                let rootNodeCopy = copyTreeNode(node: rootNode, newResume: newResume)
                newResume.rootNode = rootNodeCopy
            }

            // Step 3: Save the new resume to the context
            context.insert(newResume)

            do {
                try context.save()
                Logger.debug("Successfully saved duplicate resume")
            } catch {
                Logger.debug("Error saving duplicate resume: \(error)")
                return nil
            }

            return newResume
        } else {
            Logger.debug("No job app associated with resume")
            return nil
        }
    }

    // Recursive function to copy a TreeNode and its children
    func copyTreeNode(node: TreeNode, newResume: Resume) -> TreeNode {
        // Step 1: Create a copy of the current node with the new resume reference
        let copyNode = TreeNode(
            name: node.name,
            value: node.value,
            parent: nil, // The parent will be set during recursion
            inEditor: node.includeInEditor,
            status: node.status,
            resume: newResume
        )

        // Step 2: Recursively copy the children and set the parent-child relationship
        if let children = node.children {
            for child in children {
                let childCopy = copyTreeNode(node: child, newResume: newResume)
                copyNode.addChild(childCopy) // Attach the child to the copied parent
            }
        }

        // Return the copied node
        return copyNode
    }

    func updateResumeTree(resume: Resume, rootNode: TreeNode) {
        resume.rootNode = rootNode
        saveContext()
        resume.debounceExport() // Update JSON, PDF, etc.
    }

    func deleteRes(_ res: Resume) {
        // Handle jobApp relationship updates and remove the resume from the jobApp
        if let jobApp = res.jobApp {
            // First update selection if needed
            jobApp.resumeDeletePrep(candidate: res)

            // Then remove from the array if it exists
            if let parentIndex = jobApp.resumes.firstIndex(of: res) {
                jobApp.resumes.remove(at: parentIndex)
            }

            // Clear the reference to prevent invalid access
            res.jobApp = nil
        }

        // Clear references to prevent potential access to deleted objects
        res.rootNode = nil
        res.enabledSources = []
        res.model = nil

        // Delete the resume and save
        modelContext.delete(res)
        saveContext()
    }

    // Form functionality incomplete

    // `saveContext()` now lives in `SwiftDataStore`.
}
