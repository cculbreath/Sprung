//
//  ResStore.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//

//
//  swift
//  Sprung
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
    private let templateSeedStore: TemplateSeedStore

    // MARK: - Initialiser

    init(
        context: ModelContext,
        exportCoordinator: ResumeExportCoordinator,
        templateSeedStore: TemplateSeedStore
    ) {
        modelContext = context
        self.exportCoordinator = exportCoordinator
        self.templateSeedStore = templateSeedStore
    }

    @discardableResult
    func create(jobApp: JobApp, sources: [ResRef], template: Template) -> Resume? {
        // ModelContext is guaranteed to exist
        let modelContext = self.modelContext

        let resume = Resume(jobApp: jobApp, enabledSources: sources, template: template)

        if jobApp.selectedRes == nil {
            jobApp.selectedRes = resume
        }
        
        // Update job app status from 'new' to 'inProgress' when creating first resume
        if jobApp.status == .new {
            jobApp.status = .inProgress
        }

        let contextBuilder = ResumeTemplateContextBuilder(templateSeedStore: templateSeedStore)
        let applicantProfile = ApplicantProfileManager.shared.getProfile()
        guard let context = contextBuilder.buildContext(
            for: template,
            fallbackJSON: nil,
            applicantProfile: applicantProfile
        ) else {
            Logger.error("ResStore.create: Failed to build resume context dictionary for template \(template.slug)")
            return nil
        }

        let manifest = TemplateManifestLoader.manifest(for: template)

        guard let rootNode = buildTree(
            for: resume,
            context: context,
            manifest: manifest
        ) else {
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

    private func buildTree(
        for resume: Resume,
        context: [String: Any],
        manifest: TemplateManifest?
    ) -> TreeNode? {
        let builder = JsonToTree(
            resume: resume,
            context: context,
            manifest: manifest
        )
        guard let root = builder.buildTree() else {
            return nil
        }
        return root
    }

    @discardableResult
    func duplicate(_ originalResume: Resume) -> Resume? {
        guard let jobApp = originalResume.jobApp else { return nil }
        
        // Create new resume with same sources and template
        let newResume = Resume(
            jobApp: jobApp,
            enabledSources: originalResume.enabledSources,
            template: originalResume.template
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
        newNode.schemaKey = original.schemaKey
        newNode.schemaInputKindRaw = original.schemaInputKindRaw
        newNode.schemaRequired = original.schemaRequired
        newNode.schemaRepeatable = original.schemaRepeatable
        newNode.schemaPlaceholder = original.schemaPlaceholder
        newNode.schemaTitleTemplate = original.schemaTitleTemplate
        newNode.schemaValidationRule = original.schemaValidationRule
        newNode.schemaValidationMessage = original.schemaValidationMessage
        newNode.schemaValidationPattern = original.schemaValidationPattern
        newNode.schemaValidationMin = original.schemaValidationMin
        newNode.schemaValidationMax = original.schemaValidationMax
        newNode.schemaValidationOptions = original.schemaValidationOptions
        newNode.schemaSourceKey = original.schemaSourceKey

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

        // Delete the resume and save
        modelContext.delete(res)
        saveContext()
    }

    // Form functionality incomplete

    // `saveContext()` now lives in `SwiftDataStore`.
}
