//
//  ResStore.swift
//  Sprung
//
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
    private let experienceDefaultsStore: ExperienceDefaultsStore
    // MARK: - Initialiser
    init(
        context: ModelContext,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        experienceDefaultsStore: ExperienceDefaultsStore
    ) {
        modelContext = context
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
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
        guard let manifest = TemplateManifestLoader.manifest(for: template) else {
            Logger.error("ResStore.create: No manifest found for template \(template.slug)")
            return nil
        }
        let experienceDefaults = experienceDefaultsStore.currentDefaults()
        let treeBuilder = ExperienceDefaultsToTree(
            resume: resume,
            experienceDefaults: experienceDefaults,
            manifest: manifest
        )
        guard let rootNode = treeBuilder.buildTree() else {
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
    // `saveContext()` now lives in `SwiftDataStore`.
}
