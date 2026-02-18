//
//  ExperienceDefaultsToTree.swift
//  Sprung
//
//  Builds TreeNode hierarchy directly from ExperienceDefaults.
//  Replaces the old JsonToTree + ResumeTemplateContextBuilder pipeline.
//

import Foundation

/// Builds TreeNode hierarchy directly from ExperienceDefaults using the template manifest.
///
/// Key design principles:
/// - No intermediate dictionary conversion
/// - Uses typed Swift models (WorkExperienceDefault, EducationExperienceDefault, etc.)
/// - Manifest controls structure, field visibility, and hiddenFields
/// - basics section is NEVER created (profile comes fresh at render time)
/// - Custom fields go under "custom" section
@MainActor
final class ExperienceDefaultsToTree {
    let resume: Resume
    let experienceDefaults: ExperienceDefaults
    let manifest: TemplateManifest
    var hiddenFieldPaths: Set<String> = []

    init(resume: Resume, experienceDefaults: ExperienceDefaults, manifest: TemplateManifest) {
        self.resume = resume
        self.experienceDefaults = experienceDefaults
        self.manifest = manifest
        buildHiddenFieldPaths()
    }

    // MARK: - Public API

    func buildTree() -> TreeNode? {
        let root = TreeNode(
            name: "root",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        )

        // Build sections in manifest order
        for sectionKey in manifest.sectionOrder where shouldIncludeSection(sectionKey) {
            buildSection(key: sectionKey, parent: root)
        }

        // Build editable template fields (fontSizes under styling, sectionLabels)
        buildEditableTemplateFields(parent: root)

        // Apply default AI fields from manifest
        if let defaultFields = manifest.defaultAIFields, !defaultFields.isEmpty {
            Logger.info("🎯 [buildTree] Applying \(defaultFields.count) defaultAIFields patterns")
            applyDefaultAIFields(to: root, patterns: defaultFields)
        } else {
            Logger.warning("🎯 [buildTree] No defaultAIFields in manifest (defaultAIFields: \(manifest.defaultAIFields?.description ?? "nil"))")
        }

        return root
    }

    // MARK: - Section Building

    private func shouldIncludeSection(_ key: String) -> Bool {
        // Skip basics - profile data comes fresh from ApplicantProfile at render time
        if key == "basics" { return false }

        // Skip sections with special behaviors
        if let behavior = manifest.behavior(forSection: key),
           [.styling, .includeFonts, .editorKeys, .metadata].contains(behavior) {
            return false
        }

        // Check if section is enabled in ExperienceDefaults
        return isSectionEnabled(key)
    }

    private func isSectionEnabled(_ key: String) -> Bool {
        switch key {
        case ExperienceSectionKey.work.rawValue: return experienceDefaults.isWorkEnabled && !experienceDefaults.work.isEmpty
        case ExperienceSectionKey.volunteer.rawValue: return experienceDefaults.isVolunteerEnabled && !experienceDefaults.volunteer.isEmpty
        case ExperienceSectionKey.education.rawValue: return experienceDefaults.isEducationEnabled && !experienceDefaults.education.isEmpty
        case ExperienceSectionKey.projects.rawValue: return experienceDefaults.isProjectsEnabled && !experienceDefaults.projects.isEmpty
        case ExperienceSectionKey.skills.rawValue: return experienceDefaults.isSkillsEnabled && !experienceDefaults.skills.isEmpty
        case ExperienceSectionKey.awards.rawValue: return experienceDefaults.isAwardsEnabled && !experienceDefaults.awards.isEmpty
        case ExperienceSectionKey.certificates.rawValue: return experienceDefaults.isCertificatesEnabled && !experienceDefaults.certificates.isEmpty
        case ExperienceSectionKey.publications.rawValue: return experienceDefaults.isPublicationsEnabled && !experienceDefaults.publications.isEmpty
        case ExperienceSectionKey.languages.rawValue: return experienceDefaults.isLanguagesEnabled && !experienceDefaults.languages.isEmpty
        case ExperienceSectionKey.interests.rawValue: return experienceDefaults.isInterestsEnabled && !experienceDefaults.interests.isEmpty
        case ExperienceSectionKey.references.rawValue: return experienceDefaults.isReferencesEnabled && !experienceDefaults.references.isEmpty
        case ExperienceSectionKey.custom.rawValue:
            // Include custom section if user has data OR manifest defines custom fields
            let hasUserData = !experienceDefaults.customFields.isEmpty
            let hasManifestFields = !(manifest.section(for: key)?.fields.isEmpty ?? true)
            return hasUserData || hasManifestFields
        default: return true // Allow manifest-defined sections we don't have explicit data for
        }
    }

    private func buildSection(key: String, parent: TreeNode) {
        switch key {
        case ExperienceSectionKey.work.rawValue:
            buildWorkSection(parent: parent)
        case ExperienceSectionKey.volunteer.rawValue:
            buildVolunteerSection(parent: parent)
        case ExperienceSectionKey.education.rawValue:
            buildEducationSection(parent: parent)
        case ExperienceSectionKey.projects.rawValue:
            buildProjectsSection(parent: parent)
        case ExperienceSectionKey.skills.rawValue:
            buildSkillsSection(parent: parent)
        case ExperienceSectionKey.awards.rawValue:
            buildAwardsSection(parent: parent)
        case ExperienceSectionKey.certificates.rawValue:
            buildCertificatesSection(parent: parent)
        case ExperienceSectionKey.publications.rawValue:
            buildPublicationsSection(parent: parent)
        case ExperienceSectionKey.languages.rawValue:
            buildLanguagesSection(parent: parent)
        case ExperienceSectionKey.interests.rawValue:
            buildInterestsSection(parent: parent)
        case ExperienceSectionKey.references.rawValue:
            buildReferencesSection(parent: parent)
        case ExperienceSectionKey.custom.rawValue:
            buildCustomSection(parent: parent)
        default:
            break // Unknown section
        }
    }

    // MARK: - Editor Label Helper

    /// Apply editor label from manifest if available
    func applyEditorLabel(to node: TreeNode, for key: String) {
        if let label = manifest.editorLabels?[key] {
            node.editorLabel = label
        }
    }

    // MARK: - Field Helpers

    func addFieldIfNotHidden(
        _ fieldName: String,
        value: String,
        parent: TreeNode,
        path: [String],
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) {
        let fieldPath = path + [fieldName]
        guard !isFieldHidden(path: fieldPath) else { return }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let childDescriptor = descriptor?.children?.first(where: { $0.key == fieldName })
        let node = parent.addChild(TreeNode(
            name: fieldName,
            value: value,
            inEditor: true,
            status: .saved,
            resume: resume
        ))
        node.applyDescriptor(childDescriptor)
    }

    func addHighlightsIfNotHidden(
        _ highlights: [String],
        parent: TreeNode,
        path: [String],
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) {
        let fieldPath = path + ["highlights"]
        guard !isFieldHidden(path: fieldPath) else { return }
        let nonEmptyHighlights = highlights.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyHighlights.isEmpty else { return }

        let childDescriptor = descriptor?.children?.first(where: { $0.key == "highlights" })
        let container = parent.addChild(TreeNode(
            name: "highlights",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        container.schemaAllowsChildMutation = childDescriptor?.allowsManualMutations ?? false
        container.applyDescriptor(childDescriptor)

        for highlight in nonEmptyHighlights {
            _ = container.addChild(TreeNode(
                name: "",
                value: highlight,
                inEditor: true,
                status: .saved,
                resume: resume
            ))
        }
    }

    func addKeywordsIfNotHidden(
        _ keywords: [String],
        parent: TreeNode,
        path: [String],
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) {
        let fieldPath = path + ["keywords"]
        guard !isFieldHidden(path: fieldPath) else { return }
        let nonEmptyKeywords = keywords.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyKeywords.isEmpty else { return }

        let childDescriptor = descriptor?.children?.first(where: { $0.key == "keywords" })
        let container = parent.addChild(TreeNode(
            name: "keywords",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        container.schemaAllowsChildMutation = childDescriptor?.allowsManualMutations ?? false
        container.applyDescriptor(childDescriptor)

        for keyword in nonEmptyKeywords {
            _ = container.addChild(TreeNode(
                name: "",
                value: keyword,
                inEditor: true,
                status: .saved,
                resume: resume
            ))
        }
    }

    func addCoursesIfNotHidden(
        _ courses: [String],
        parent: TreeNode,
        path: [String],
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) {
        let fieldPath = path + ["courses"]
        guard !isFieldHidden(path: fieldPath) else { return }
        let nonEmptyCourses = courses.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyCourses.isEmpty else { return }

        let childDescriptor = descriptor?.children?.first(where: { $0.key == "courses" })
        let container = parent.addChild(TreeNode(
            name: "courses",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        container.schemaAllowsChildMutation = childDescriptor?.allowsManualMutations ?? false
        container.applyDescriptor(childDescriptor)

        for course in nonEmptyCourses {
            _ = container.addChild(TreeNode(
                name: "",
                value: course,
                inEditor: true,
                status: .saved,
                resume: resume
            ))
        }
    }

    func addRolesIfNotHidden(
        _ roles: [String],
        parent: TreeNode,
        path: [String],
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) {
        let fieldPath = path + ["roles"]
        guard !isFieldHidden(path: fieldPath) else { return }
        let nonEmptyRoles = roles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyRoles.isEmpty else { return }

        let childDescriptor = descriptor?.children?.first(where: { $0.key == "roles" })
        let container = parent.addChild(TreeNode(
            name: "roles",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        container.schemaAllowsChildMutation = childDescriptor?.allowsManualMutations ?? false
        container.applyDescriptor(childDescriptor)

        for role in nonEmptyRoles {
            _ = container.addChild(TreeNode(
                name: "",
                value: role,
                inEditor: true,
                status: .saved,
                resume: resume
            ))
        }
    }

    // MARK: - Hidden Fields

    private func buildHiddenFieldPaths() {
        for (sectionKey, section) in manifest.sections {
            guard let hidden = section.hiddenFields else { continue }
            for field in hidden {
                hiddenFieldPaths.insert("\(sectionKey).\(field)")
            }
        }
    }

    func isFieldHidden(path: [String]) -> Bool {
        guard path.count >= 2 else { return false }
        let sectionKey = path[0]
        guard let fieldName = path.last else { return false }
        return hiddenFieldPaths.contains("\(sectionKey).\(fieldName)")
    }
}
