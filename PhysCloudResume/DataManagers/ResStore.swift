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
    private let exportCoordinator: ResumeExportCoordinator
    private let templateStore: TemplateStore
    private let templateSeedStore: TemplateSeedStore

    // MARK: - Initialiser

    init(
        context: ModelContext,
        exportCoordinator: ResumeExportCoordinator,
        templateStore: TemplateStore,
        templateSeedStore: TemplateSeedStore
    ) {
        modelContext = context
        self.exportCoordinator = exportCoordinator
        self.templateStore = templateStore
        self.templateSeedStore = templateSeedStore
    }

    @discardableResult
    func create(jobApp: JobApp, sources: [ResRef], model: ResModel) -> Resume? {
        // ModelContext is guaranteed to exist
        let modelContext = self.modelContext

        let resume = Resume(jobApp: jobApp, enabledSources: sources, model: model)

        if jobApp.selectedRes == nil {
            jobApp.selectedRes = resume
        }
        
        // Update job app status from 'new' to 'inProgress' when creating first resume
        if jobApp.status == .new {
            jobApp.status = .inProgress
        }

        guard let template = resolveTemplate(for: model) else {
            Logger.error("ResStore.create: Unable to resolve template for style \(model.style)")
            return nil
        }
        resume.template = template

        let contextBuilder = ResumeTemplateContextBuilder(templateSeedStore: templateSeedStore)
        let applicantProfile = ApplicantProfileManager.shared.getProfile()
        let seededJSON = contextBuilder.buildJSONString(
            for: template,
            fallbackJSON: model.json,
            applicantProfile: applicantProfile
        ) ?? model.json

        guard let rootNode = buildTree(for: resume, jsonString: seededJSON) else {
            Logger.error("ResStore.create: Failed to build resume tree for template \(template.slug)")
            return nil
        }
        resume.rootNode = rootNode

        // Persist new resume (and trigger observers)
        jobApp.addResume(resume)
        modelContext.insert(resume)
        saveContext()

        exportCoordinator.debounceExport(resume: resume)

        return resume
    }

    private func resolveTemplate(for model: ResModel) -> Template? {
        let normalizedStyle = model.style.lowercased()
        if let templateEntity = templateStore.template(slug: normalizedStyle) {
            return templateEntity
        }
        return templateStore.template(slug: "archer")
    }

    private func buildTree(for resume: Resume, jsonString: String) -> TreeNode? {
        guard let builder = JsonToTree(resume: resume, rawJson: jsonString) else {
            return nil
        }
        return builder.buildTree()
    }

    @discardableResult
    func duplicate(_ originalResume: Resume) -> Resume? {
        guard let jobApp = originalResume.jobApp,
              let model = originalResume.model else { return nil }
        
        // Create new resume with same sources and model
        let newResume = Resume(
            jobApp: jobApp,
            enabledSources: originalResume.enabledSources,
            model: model
        )
        
        // Copy basic properties
        newResume.includeFonts = originalResume.includeFonts
        newResume.keyLabels = originalResume.keyLabels
        newResume.importedEditorKeysData = originalResume.importedEditorKeysData
        newResume.template = originalResume.template
        
        // Deep copy the tree structure
        if let originalRoot = originalResume.rootNode {
            newResume.rootNode = duplicateTreeNode(originalRoot, for: newResume)
        }
        
        // Deep copy font size nodes if they exist
        if originalResume.includeFonts && !originalResume.fontSizeNodes.isEmpty {
            newResume.fontSizeNodes = originalResume.fontSizeNodes.map { originalNode in
                duplicateFontSizeNode(originalNode, for: newResume)
            }
        }
        
        // Add to jobApp and save
        jobApp.addResume(newResume)
        modelContext.insert(newResume)
        saveContext()
        
        // Trigger export for the new resume
        exportCoordinator.debounceExport(resume: newResume)
        
        return newResume
    }
    
    private func duplicateTreeNode(_ original: TreeNode, for resume: Resume, parent: TreeNode? = nil) -> TreeNode {
        let newNode = TreeNode(
            name: original.name,
            value: original.value,
            children: nil,
            parent: parent,
            inEditor: original.includeInEditor,
            status: original.status,
            resume: resume,
            isTitleNode: original.isTitleNode
        )
        
        newNode.myIndex = original.myIndex
        newNode.depth = original.depth
        
        // Recursively duplicate children
        if let originalChildren = original.children {
            newNode.children = originalChildren.map { child in
                duplicateTreeNode(child, for: resume, parent: newNode)
            }
        }
        
        return newNode
    }
    
    private func duplicateFontSizeNode(_ original: FontSizeNode, for resume: Resume) -> FontSizeNode {
        return FontSizeNode(
            key: original.key,
            index: original.index,
            fontString: original.fontString,
            resume: resume
        )
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
