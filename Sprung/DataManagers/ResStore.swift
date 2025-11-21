//
//  ResStore.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//
import Foundation
import SwiftData
import SwiftUI
@Observable
@MainActor
final class ResStore: SwiftDataStore {
    // MARK: - Properties
    unowned let modelContext: ModelContext
    private let exportCoordinator: ResumeExportCoordinator
    private let applicantProfileStore: ApplicantProfileStore
    private let templateSeedStore: TemplateSeedStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    // MARK: - Initialiser
    init(
        context: ModelContext,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        templateSeedStore: TemplateSeedStore,
        experienceDefaultsStore: ExperienceDefaultsStore
    ) {
        modelContext = context
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
        self.templateSeedStore = templateSeedStore
        self.experienceDefaultsStore = experienceDefaultsStore
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
        let contextBuilder = ResumeTemplateContextBuilder(
            templateSeedStore: templateSeedStore,
            experienceDefaultsStore: experienceDefaultsStore
        )
        let applicantProfile = applicantProfileStore.currentProfile()
        guard let context = contextBuilder.buildContext(
            for: template,
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.1)) {
            jobApp.addResume(resume)
        }
        modelContext.insert(resume)
        saveContext()

        Task { @MainActor in
            do {
                try await exportCoordinator.ensureFreshRenderedText(for: resume)
            } catch {
                Logger.error("ResStore.create: Failed to render initial PDF for resume \(resume.id): \(error)")
            }
        }
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.1)) {
            jobApp.addResume(newResume)
        }
        modelContext.insert(newResume)
        saveContext()

        // Trigger export for the new resume
        Task { @MainActor in
            do {
                try await exportCoordinator.ensureFreshRenderedText(for: newResume)
            } catch {
                Logger.error("ResStore.duplicate: Failed to render PDF for duplicated resume \(newResume.id): \(error)")
            }
        }

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
        newNode.editorLabel = original.editorLabel
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
        newNode.schemaAllowsChildMutation = original.schemaAllowsChildMutation
        newNode.schemaAllowsNodeDeletion = original.schemaAllowsNodeDeletion
        newNode.editorTransparent = original.editorTransparent
        // Recursively duplicate children
        if let originalChildren = original.children {
            newNode.children = originalChildren.map { child in
                duplicateTreeNode(child, for: resume, parent: newNode)
            }
        }
        // Recursively duplicate viewChildren (references to data nodes)
        // Note: viewChildren are references to nodes in the children tree,
        // so we need to map them to the corresponding new nodes
        if let originalViewChildren = original.viewChildren {
            newNode.viewChildren = originalViewChildren.map { viewChild in
                // Find the corresponding new node by matching the original's id
                findCorrespondingNode(in: newNode, matching: viewChild) ?? viewChild
            }
        }
        return newNode
    }
    private func findCorrespondingNode(in newTree: TreeNode, matching original: TreeNode) -> TreeNode? {
        // Simple approach: find by name and path
        // This assumes the structure is identical, which it should be for duplicates
        if newTree.name == original.name && newTree.value == original.value {
            return newTree
        }
        guard let children = newTree.children else { return nil }
        for child in children {
            if let found = findCorrespondingNode(in: child, matching: original) {
                return found
            }
        }
        return nil
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
    // `saveContext()` now lives in `SwiftDataStore`.
}
