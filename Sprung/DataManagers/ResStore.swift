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
    private let experienceDefaultsStore: ExperienceDefaultsStore
    // MARK: - Initialiser
    init(
        context: ModelContext,
        exportCoordinator: ResumeExportCoordinator,
        experienceDefaultsStore: ExperienceDefaultsStore
    ) {
        modelContext = context
        self.exportCoordinator = exportCoordinator
        self.experienceDefaultsStore = experienceDefaultsStore
    }
    @discardableResult
    func create(jobApp: JobApp, sources: [KnowledgeCard], template: Template) -> Resume? {
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

        // Apply manifest's reviewPhases defaults to resume.phaseAssignments
        applyManifestPhaseDefaults(to: resume, from: manifest)

        // Create FontSizeNodes from manifest styling section
        buildFontSizeNodes(for: resume, from: manifest)

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

    /// Creates FontSizeNode objects from the manifest's styling section.
    private func buildFontSizeNodes(for resume: Resume, from manifest: TemplateManifest) {
        guard let stylingSection = manifest.section(for: "styling"),
              let defaultContext = stylingSection.defaultContextValue() as? [String: Any] else {
            return
        }

        // Check if fonts should be included
        let includeFonts = defaultContext["includeFonts"] as? Bool ?? false
        guard includeFonts,
              let fontSizes = defaultContext["fontSizes"] as? [String: String],
              !fontSizes.isEmpty else {
            return
        }

        resume.includeFonts = true

        // Use fontSizeOrder array if present to preserve manifest order,
        // otherwise fall back to alphabetical sorting
        let orderedKeys: [String]
        if let fontSizeOrder = defaultContext["fontSizeOrder"] as? [String] {
            // Use explicit order, appending any keys not in the order array
            let orderSet = Set(fontSizeOrder)
            let extraKeys = fontSizes.keys.filter { !orderSet.contains($0) }.sorted()
            orderedKeys = fontSizeOrder.filter { fontSizes[$0] != nil } + extraKeys
        } else {
            orderedKeys = fontSizes.keys.sorted()
        }

        for (index, key) in orderedKeys.enumerated() {
            guard let value = fontSizes[key] else { continue }
            let node = FontSizeNode(
                key: key,
                index: index,
                fontString: value,
                resume: resume
            )
            resume.fontSizeNodes.append(node)
        }
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

    /// Apply manifest's reviewPhases defaults to resume.phaseAssignments
    /// Only phase 1 assignments are stored; phase 2 is the default (absence = phase 2)
    private func applyManifestPhaseDefaults(to resume: Resume, from manifest: TemplateManifest) {
        guard let reviewPhases = manifest.reviewPhases else { return }

        var assignments = resume.phaseAssignments
        for (section, phases) in reviewPhases {
            for phaseConfig in phases {
                // Extract attribute name from field pattern (e.g., "skills.*.name" -> "name")
                let attrName = phaseConfig.field.split(separator: ".").last.map(String.init) ?? phaseConfig.field
                let key = "\(section.capitalized)-\(attrName)"
                // Only store phase 1 assignments; phase 2 is the default
                if phaseConfig.phase == 1 {
                    assignments[key] = 1
                }
                // Don't store phase 2 - absence means phase 2
            }
        }
        resume.phaseAssignments = assignments
    }
}
