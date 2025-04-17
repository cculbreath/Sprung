//
//  swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/30/24.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class ResStore {
    // MARK: - Properties

    private unowned let modelContext: ModelContext

    // Computed collection that always reflects current SwiftData contents.
    var resumes: [Resume] {
        (try? modelContext.fetch(FetchDescriptor<Resume>())) ?? []
    }

    private var changeToken: Int = 0

    // MARK: - Initialiser

    init(context: ModelContext) {
        self.modelContext = context

    }



    @discardableResult
    func addResume(res: Resume, to jobApp: JobApp) -> Resume {
        print("Current resumes count: \(res.jobApp!.resumes.count)")

        jobApp.addResume(res)
        res.model!.resumes.append(res)
        modelContext.insert(res)
        try? modelContext.save()
        withAnimation { changeToken += 1 }
        print("ResStore resume added, jobApp.hasAnyResume is \(jobApp.hasAnyRes ? "true" : "false")")
        return res
    }

    @discardableResult
    func create(jobApp: JobApp, sources: [ResRef], model: ResModel) -> Resume? {
        // ModelContext is guaranteed to exist
        let modelContext = self.modelContext
        print("Model context available")
            print("Creating resume for job application: \(jobApp)")
            print("Current resumes count: \(jobApp.resumes.count)")

            let resume = Resume(jobApp: jobApp, enabledSources: sources, model: model)
            print("Current resumes count: \(resume.jobApp!.resumes.count)")

            if jobApp.selectedRes == nil {
                print("Set Selection")

                jobApp.selectedRes = resume
            }
            print("Resume object created")

            do {
                guard let builder = JsonToTree(resume: resume, rawJson: model.json) else {
                    return nil
                }
                resume.rootNode = builder.buildTree()
                print("Resume tree built from JSON data")
                print("1 Current resumes count: \(resume.jobApp!.resumes.count)")
//                print(builder.json)

                // Persist new resume (and trigger observers)
                jobApp.addResume(resume)
                modelContext.insert(resume)
                try? modelContext.save()
                withAnimation { changeToken += 1 }

                print("2 Current resumes count: \(resume.jobApp!.resumes.count)")

                print("Resume successfully saved and processed")
                resume.debounceExport()

            } catch {
                print("Could not unwrap JSON")
            }
            return resume
    }

    func createDuplicate(originalResume: Resume, context: ModelContext) -> Resume? {
        // Step 1: Create a new Resume instance
        if let jobAppo = originalResume.jobApp {
            let newResume = Resume(jobApp: jobAppo, enabledSources: originalResume.enabledSources, model: originalResume.model!)
            TreeNode.childIndexer = 0

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
                print("Failed to save duplicated resume: \(error)")
                return nil
            }

            return newResume
        } else { return nil }
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

        // Add the copied node to the new resume's nodes array
        newResume.nodes.append(copyNode)

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
        try? modelContext.save()
        resume.debounceExport() // Update JSON, PDF, etc.
    }

    func deleteRes(_ res: Resume) {
        if let rootNode = res.rootNode {
            TreeNode.deleteTreeNode(node: rootNode, context: modelContext)
        }

        if let jobApp = res.jobApp, let parentIndex = jobApp.resumes.firstIndex(of: res) {
            jobApp.resumeDeletePrep(candidate: res)
            jobApp.resumes.remove(at: parentIndex)
        }

        modelContext.delete(res)
        try? modelContext.save()
        withAnimation { changeToken += 1 }
    }

    // Form functionality incomplete
    //    private func populateFormFromObj(_ resRef: JobApp) {
    //        form.populateFormFromObj(jobApp)
    //    }
    //
    //
    //    func editWithForm(_ jobApp:JobApp? = nil) {
    //        let jobAppEditing = jobApp ?? selectedApp
    //        guard let jobAppEditing = jobAppEditing else {
    //            fatalError("No job application available to edit.")
    //        }
    //        self.populateFormFromObj(jobAppEditing)
    //    }
    //    func cancelFormEdit(_ jobApp:JobApp? = nil) {
    //        let jobAppEditing = jobApp ?? selectedApp
    //        guard let jobAppEditing = jobAppEditing else {
    //            fatalError("No job application available to restore state.")
    //        }
    //        self.populateFormFromObj(jobAppEditing)
    //    }
    //
    //    func saveForm(_ jobApp:JobApp? = nil) {
    //        let jobAppToSave = jobApp ?? selectedApp
    //        guard let jobAppToSave = jobAppToSave else {
    //            fatalError("No job application available to save.")
    //        }
    //        jobAppToSave.assignPropsFromForm(form)
    //        saveContext()
    //
    //    }

    // Save changes to the database
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
