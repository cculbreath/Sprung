//
//  swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/30/24.
//

import Foundation
import SwiftData

@Observable
final class ResStore {
    var resumes: [Resume] = []

    private var modelContext: ModelContext?
    init() {}
    func initialize(context: ModelContext) {
        modelContext = context
        loadResumes() // Load data from the database when the store is initialized
    }

    private func loadResumes() {
        let descriptor = FetchDescriptor<Resume>()
        do {
            resumes = try modelContext!.fetch(descriptor)
        } catch {
            print("Failed to fetch Resume Refs: \(error)")
        }
    }

    @discardableResult
    func addResume(res: Resume, to jobApp: JobApp) -> Resume {
        print("Current resumes count: \(res.jobApp!.resumes.count)")

        resumes.append(res)
        jobApp.addResume(res)
        res.model!.resumes.append(res)
        modelContext!.insert(res)
        saveContext()
        print("ResStore resume added, jobApp.hasAnyResume is \(jobApp.hasAnyRes ? "true" : "false")")
        return res
    }

    @discardableResult
    func create(jobApp: JobApp, sources: [ResRef], model: ResModel) -> Resume? {
        if let modelContext = modelContext {
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

            guard let jsonData = model.json.data(using: .utf8) else {
                print("Error converting JSON content to data")
                return nil
            }

            resume.rootNode = resume.buildTree(from: jsonData, res: resume)
            print("Resume tree built from JSON data")
            print("1 Current resumes count: \(resume.jobApp!.resumes.count)")
            addResume(res: resume, to: jobApp)

            // Insert resume into the model context and save
            modelContext.insert(resume)
            print("2 Current resumes count: \(resume.jobApp!.resumes.count)")

            do {
                try modelContext.save()
                print("Model context saved after processing JSON data")
                print("3 Current resumes count: \(resume.jobApp!.resumes.count)")

            } catch {
                print("Error saving context: \(error)")
                return nil
            }

            print("Resume successfully saved and processed")
            resume.debounceExport()
            return resume
        } else {
            print("No JSON source found")
            return nil
        }
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
        try? modelContext?.save()
        resume.debounceExport() // Update JSON, PDF, etc.
    }

    func deleteRes(_ res: Resume) {
        if let index = resumes.firstIndex(of: res) {
            if let rootNode = res.rootNode {
                TreeNode.deleteTreeNode(node: rootNode, context: modelContext!) // Recursively delete rootNode and its children
            }
            if let jobApp = res.jobApp, let parentindex = jobApp.resumes.firstIndex(of: res) {
                jobApp.resumeDeletePrep(candidate: res)
                jobApp.resumes.remove(at: parentindex)
            }
            resumes.remove(at: index)
            modelContext!.delete(res)
            saveContext()
        } else {
            print("no rootnode")
        }
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
            try modelContext!.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
