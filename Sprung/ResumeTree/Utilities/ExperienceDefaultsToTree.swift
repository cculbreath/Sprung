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
    private let resume: Resume
    private let experienceDefaults: ExperienceDefaults
    private let manifest: TemplateManifest
    private var hiddenFieldPaths: Set<String> = []

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

    // MARK: - Work Section

    private func buildWorkSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.work.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.work.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.work.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true
        container.schemaAllowsNodeDeletion = entryDescriptor?.allowsManualMutations ?? true

        for (index, work) in experienceDefaults.work.enumerated() {
            let title = work.name.isEmpty ? "Work \(index + 1)" : work.name
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = work.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["work", "\(index)"]
            addFieldIfNotHidden("name", value: work.name, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("position", value: work.position, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("location", value: work.location, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("url", value: work.url, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("startDate", value: work.startDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("endDate", value: work.endDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("summary", value: work.summary, parent: entry, path: path, descriptor: entryDescriptor)
            addHighlightsIfNotHidden(work.highlights.map { $0.text }, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Volunteer Section

    private func buildVolunteerSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.volunteer.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.volunteer.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.volunteer.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, volunteer) in experienceDefaults.volunteer.enumerated() {
            let title = volunteer.organization.isEmpty ? "Volunteer \(index + 1)" : volunteer.organization
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = volunteer.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["volunteer", "\(index)"]
            addFieldIfNotHidden("organization", value: volunteer.organization, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("position", value: volunteer.position, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("url", value: volunteer.url, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("startDate", value: volunteer.startDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("endDate", value: volunteer.endDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("summary", value: volunteer.summary, parent: entry, path: path, descriptor: entryDescriptor)
            addHighlightsIfNotHidden(volunteer.highlights.map { $0.text }, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Education Section

    private func buildEducationSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.education.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.education.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.education.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, education) in experienceDefaults.education.enumerated() {
            let title = education.institution.isEmpty ? "Education \(index + 1)" : education.institution
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = education.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["education", "\(index)"]
            addFieldIfNotHidden("institution", value: education.institution, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("url", value: education.url, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("area", value: education.area, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("studyType", value: education.studyType, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("startDate", value: education.startDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("endDate", value: education.endDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("score", value: education.score, parent: entry, path: path, descriptor: entryDescriptor)
            addCoursesIfNotHidden(education.courses.map { $0.name }, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Projects Section

    private func buildProjectsSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.projects.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.projects.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.projects.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, project) in experienceDefaults.projects.enumerated() {
            let title = project.name.isEmpty ? "Project \(index + 1)" : project.name
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = project.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["projects", "\(index)"]
            addFieldIfNotHidden("name", value: project.name, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("description", value: project.description, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("startDate", value: project.startDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("endDate", value: project.endDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("url", value: project.url, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("entity", value: project.organization, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("type", value: project.type, parent: entry, path: path, descriptor: entryDescriptor)
            addHighlightsIfNotHidden(project.highlights.map { $0.text }, parent: entry, path: path, descriptor: entryDescriptor)
            addKeywordsIfNotHidden(project.keywords.map { $0.keyword }, parent: entry, path: path, descriptor: entryDescriptor)
            addRolesIfNotHidden(project.roles.map { $0.role }, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Skills Section

    private func buildSkillsSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.skills.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.skills.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.skills.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, skill) in experienceDefaults.skills.enumerated() {
            let title = skill.name.isEmpty ? "Skill \(index + 1)" : skill.name
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = skill.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["skills", "\(index)"]
            addFieldIfNotHidden("name", value: skill.name, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("level", value: skill.level, parent: entry, path: path, descriptor: entryDescriptor)
            addKeywordsIfNotHidden(skill.keywords.map { $0.keyword }, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Awards Section

    private func buildAwardsSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.awards.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.awards.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.awards.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, award) in experienceDefaults.awards.enumerated() {
            let title = award.title.isEmpty ? "Award \(index + 1)" : award.title
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = award.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["awards", "\(index)"]
            addFieldIfNotHidden("title", value: award.title, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("date", value: award.date, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("awarder", value: award.awarder, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("summary", value: award.summary, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Certificates Section

    private func buildCertificatesSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.certificates.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.certificates.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.certificates.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, cert) in experienceDefaults.certificates.enumerated() {
            let title = cert.name.isEmpty ? "Certificate \(index + 1)" : cert.name
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = cert.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["certificates", "\(index)"]
            addFieldIfNotHidden("name", value: cert.name, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("date", value: cert.date, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("issuer", value: cert.issuer, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("url", value: cert.url, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Publications Section

    private func buildPublicationsSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.publications.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.publications.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.publications.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, pub) in experienceDefaults.publications.enumerated() {
            let title = pub.name.isEmpty ? "Publication \(index + 1)" : pub.name
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = pub.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["publications", "\(index)"]
            addFieldIfNotHidden("name", value: pub.name, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("publisher", value: pub.publisher, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("releaseDate", value: pub.releaseDate, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("url", value: pub.url, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("summary", value: pub.summary, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Languages Section

    private func buildLanguagesSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.languages.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.languages.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.languages.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, language) in experienceDefaults.languages.enumerated() {
            let title = language.language.isEmpty ? "Language \(index + 1)" : language.language
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = language.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["languages", "\(index)"]
            addFieldIfNotHidden("language", value: language.language, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("fluency", value: language.fluency, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Interests Section

    private func buildInterestsSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.interests.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.interests.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.interests.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, interest) in experienceDefaults.interests.enumerated() {
            let title = interest.name.isEmpty ? "Interest \(index + 1)" : interest.name
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = interest.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["interests", "\(index)"]
            addFieldIfNotHidden("name", value: interest.name, parent: entry, path: path, descriptor: entryDescriptor)
            addKeywordsIfNotHidden(interest.keywords.map { $0.keyword }, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - References Section

    private func buildReferencesSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.references.rawValue)
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: ExperienceSectionKey.references.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: ExperienceSectionKey.references.rawValue)
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? true

        for (index, ref) in experienceDefaults.references.enumerated() {
            let title = ref.name.isEmpty ? "Reference \(index + 1)" : ref.name
            let entry = container.addChild(TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            entry.schemaSourceKey = ref.id.uuidString
            entry.applyDescriptor(entryDescriptor)

            let path = ["references", "\(index)"]
            addFieldIfNotHidden("name", value: ref.name, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("reference", value: ref.reference, parent: entry, path: path, descriptor: entryDescriptor)
            addFieldIfNotHidden("url", value: ref.url, parent: entry, path: path, descriptor: entryDescriptor)
        }
    }

    // MARK: - Custom Section

    /// Custom fields are wrapped in a "custom" container for path matching (e.g., custom.objective).
    /// The view flattens this container - children appear at the same level as other content nodes.
    private func buildCustomSection(parent: TreeNode) {
        let section = manifest.section(for: ExperienceSectionKey.custom.rawValue)

        // Create custom container for path matching (view flattens it for display)
        let customContainer = parent.addChild(TreeNode(
            name: ExperienceSectionKey.custom.rawValue,
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))

        // Build a lookup of user data by normalized key
        // Strip "custom." prefix since manifest keys don't have it
        var userDataByKey: [String: CustomFieldValue] = [:]
        for field in experienceDefaults.customFields {
            let keyWithoutPrefix = field.key.hasPrefix("custom.") ? String(field.key.dropFirst(7)) : field.key
            let normalizedKey = keyWithoutPrefix.lowercased().filter { $0.isLetter || $0.isNumber }
            userDataByKey[normalizedKey] = field
        }

        // Get manifest-defined custom fields
        let manifestFields = section?.fields ?? []
        Logger.info("🎯 [buildCustomSection] Manifest custom fields: \(manifestFields.map { $0.key })")
        Logger.info("🎯 [buildCustomSection] User custom fields: \(experienceDefaults.customFields.map { $0.key })")

        // Track which keys we've processed (to avoid duplicates)
        var processedKeys: Set<String> = []

        // First, create nodes for all manifest-defined custom fields
        for manifestField in manifestFields {
            let fieldKey = manifestField.key
            let normalizedKey = fieldKey.lowercased().filter { $0.isLetter || $0.isNumber }
            processedKeys.insert(normalizedKey)

            // Find matching user data
            let userData = userDataByKey[normalizedKey]
            let values = userData?.values ?? []

            let fieldNode = customContainer.addChild(TreeNode(
                name: fieldKey,  // Use manifest key for consistency with patterns
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            Logger.info("🎯 [buildCustomSection] Created node name='\(fieldKey)' from manifest (userData: \(userData?.key ?? "none"))")

            // Apply editor labels
            applyEditorLabel(to: fieldNode, for: fieldKey)
            if fieldNode.editorLabel == nil {
                applyEditorLabel(to: fieldNode, for: "custom.\(fieldKey)")
            }

            // Check if this is an array field or single value
            if values.count > 1 || manifestField.repeatable == true {
                // Array of values
                for value in values {
                    _ = fieldNode.addChild(TreeNode(
                        name: "",
                        value: value,
                        inEditor: true,
                        status: .saved,
                        resume: resume
                    ))
                }
            } else if let firstValue = values.first {
                // Single value - make the field node itself the leaf
                fieldNode.value = firstValue
                fieldNode.status = .saved
            }
        }

        // Then, add any user-defined fields not in the manifest
        for field in experienceDefaults.customFields {
            let keyWithoutPrefix = field.key.hasPrefix("custom.") ? String(field.key.dropFirst(7)) : field.key
            let normalizedKey = keyWithoutPrefix.lowercased().filter { $0.isLetter || $0.isNumber }
            guard !processedKeys.contains(normalizedKey) else { continue }

            // Use key without prefix for node name to match manifest convention
            let fieldNode = customContainer.addChild(TreeNode(
                name: keyWithoutPrefix,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))

            applyEditorLabel(to: fieldNode, for: keyWithoutPrefix)
            if fieldNode.editorLabel == nil {
                applyEditorLabel(to: fieldNode, for: "custom.\(keyWithoutPrefix)")
            }

            let isRepeatable = section?.fields.first(where: { $0.key == keyWithoutPrefix })?.repeatable == true
            if field.values.count > 1 || isRepeatable {
                for value in field.values {
                    _ = fieldNode.addChild(TreeNode(
                        name: "",
                        value: value,
                        inEditor: true,
                        status: .saved,
                        resume: resume
                    ))
                }
            } else if let firstValue = field.values.first {
                fieldNode.value = firstValue
                fieldNode.status = .saved
            }
        }
    }

    // MARK: - Editable Template Fields

    /// Build editable template fields from manifest defaults.
    ///
    /// Creates two top-level nodes:
    /// - "styling": Contains fontSizes (special-cased, used by FontSizePanelView)
    /// - "template": Contains manifest-defined fields like sectionLabels (rendered generically)
    ///
    /// These are stored in TreeNode for editing and merged into context at render time.
    private func buildEditableTemplateFields(parent: TreeNode) {
        // Build styling node with fontSizes (special-cased for FontSizePanelView)
        buildStylingNode(parent: parent)

        // Build template node with manifest-defined fields (rendered generically)
        buildTemplateNode(parent: parent)
    }

    /// Build the styling node containing fontSizes.
    /// FontSizes is special-cased because it has a dedicated panel (FontSizePanelView).
    private func buildStylingNode(parent: TreeNode) {
        guard let stylingSection = manifest.section(for: "styling"),
              let defaultContext = stylingSection.defaultContextValue() as? [String: Any],
              let fontSizes = defaultContext["fontSizes"] as? [String: String],
              !fontSizes.isEmpty else { return }

        // Find or create styling node
        var stylingNode = parent.children?.first(where: { $0.name == "styling" })
        if stylingNode == nil {
            stylingNode = parent.addChild(TreeNode(
                name: "styling",
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
        }

        // Build fontSizes under styling
        if let styling = stylingNode {
            let fontSizesNode = styling.addChild(TreeNode(
                name: "fontSizes",
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            fontSizesNode.editorLabel = "Font Sizes"

            for (key, value) in fontSizes.sorted(by: { $0.key < $1.key }) {
                _ = fontSizesNode.addChild(TreeNode(
                    name: key,
                    value: value,
                    inEditor: true,
                    status: .saved,
                    resume: resume
                ))
            }
        }
    }

    /// Build the template node containing manifest-defined fields.
    /// These are rendered generically in the view (no hardcoded field names).
    private func buildTemplateNode(parent: TreeNode) {
        var templateNode: TreeNode?

        // Add sectionLabels if available
        if let labels = manifest.sectionVisibilityLabels, !labels.isEmpty {
            // Create template node on demand
            if templateNode == nil {
                templateNode = parent.addChild(TreeNode(
                    name: "template",
                    value: "",
                    inEditor: true,
                    status: .isNotLeaf,
                    resume: resume
                ))
                templateNode?.editorLabel = "Template"
            }

            let sectionLabelsNode = templateNode!.addChild(TreeNode(
                name: "sectionLabels",
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            sectionLabelsNode.editorLabel = "Section Labels"

            for (key, value) in labels.sorted(by: { $0.key < $1.key }) {
                _ = sectionLabelsNode.addChild(TreeNode(
                    name: key,
                    value: value,
                    inEditor: true,
                    status: .saved,
                    resume: resume
                ))
            }
        }

        // Future manifest-defined fields can be added here
    }

    // MARK: - Editor Label Helper

    /// Apply editor label from manifest if available
    private func applyEditorLabel(to node: TreeNode, for key: String) {
        if let label = manifest.editorLabels?[key] {
            node.editorLabel = label
        }
    }

    // MARK: - Field Helpers

    private func addFieldIfNotHidden(
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

    private func addHighlightsIfNotHidden(
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

    private func addKeywordsIfNotHidden(
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

    private func addCoursesIfNotHidden(
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

    private func addRolesIfNotHidden(
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

    private func isFieldHidden(path: [String]) -> Bool {
        guard path.count >= 2 else { return false }
        let sectionKey = path[0]
        guard let fieldName = path.last else { return false }
        return hiddenFieldPaths.contains("\(sectionKey).\(fieldName)")
    }

    // MARK: - Default AI Fields

    /// Apply defaultAIFields patterns to TreeNode state.
    ///
    /// This sets up the TreeNode as the single source of truth for AI review configuration.
    /// Patterns determine initial state; users can modify via UI (context menu toggle).
    ///
    /// # Pattern Types and TreeNode State
    ///
    /// | Pattern | TreeNode State |
    /// |---------|----------------|
    /// | `section.*.attr` | `section.bundledAttributes += [attr]` |
    /// | `section[].attr` | `section.enumeratedAttributes += [attr]` |
    /// | `section.container[]` | Each child of container marked aiToReplace |
    /// | `section.field` | field node marked aiToReplace (scalar) |
    ///
    /// # Examples
    ///
    /// | Pattern | Effect |
    /// |---------|--------|
    /// | `skills.*.name` | skills.bundledAttributes = ["name"] |
    /// | `skills[].keywords` | skills.enumeratedAttributes = ["keywords"] |
    /// | `custom.jobTitles` | jobTitles node marked aiToReplace (solo container) |
    /// | `custom.objective` | objective node marked aiToReplace |
    ///
    private func applyDefaultAIFields(to root: TreeNode, patterns: [String]) {
        Logger.debug("🎯 [applyDefaultAIFields] Starting with \(patterns.count) patterns: \(patterns)")

        for pattern in patterns {
            applyPattern(pattern, to: root)
        }
    }

    /// Apply a single pattern to the tree, setting appropriate TreeNode state.
    private func applyPattern(_ pattern: String, to root: TreeNode) {
        // Parse pattern into components, normalizing "field[]" to "field", "[]"
        var components: [String] = []
        for part in pattern.split(separator: ".") {
            let partStr = String(part)
            if partStr.hasSuffix("[]") {
                let fieldName = String(partStr.dropLast(2))
                if !fieldName.isEmpty {
                    components.append(fieldName)
                }
                components.append("[]")
            } else {
                components.append(partStr)
            }
        }

        guard !components.isEmpty else { return }

        // Identify pattern type by position of * or []
        if let starIndex = components.firstIndex(of: "*") {
            // Bundle pattern: section.*.attr
            applyBundlePattern(components: components, starIndex: starIndex, to: root)
        } else if let bracketIndex = components.firstIndex(of: "[]") {
            // Enumerate pattern
            if bracketIndex == components.count - 1 {
                // Pattern ends with []: section.container[] - enumerate container children
                applyContainerEnumeratePattern(components: components, to: root)
            } else {
                // Pattern has [] in middle: section[].attr - enumerate with specific attribute
                applyEnumeratePattern(components: components, bracketIndex: bracketIndex, to: root)
            }
        } else {
            // Scalar pattern: section.field
            applyScalarPattern(components: components, to: root)
        }
    }

    /// Apply bundle pattern (section.*.attr) - sets bundledAttributes on collection node
    private func applyBundlePattern(components: [String], starIndex: Int, to root: TreeNode) {
        // Navigate to collection node (components before *)
        let pathToCollection = Array(components[0..<starIndex])
        guard let collectionNode = findNode(path: pathToCollection, from: root) else {
            Logger.warning("🎯 [applyBundlePattern] Collection not found for path: \(pathToCollection)")
            return
        }

        // Get attribute name (components after *)
        guard starIndex + 1 < components.count else {
            Logger.warning("🎯 [applyBundlePattern] No attribute after * in pattern")
            return
        }
        let attrName = components[starIndex + 1]

        // Add to bundled attributes
        var bundled = collectionNode.bundledAttributes ?? []
        if !bundled.contains(attrName) {
            bundled.append(attrName)
            collectionNode.bundledAttributes = bundled
        }

        // Note: Don't set .aiToReplace on collection - bundledAttributes is the source of truth
        // Visual indicators come from row background color based on bundledAttributes

        Logger.info("🎯 [applyBundlePattern] Set bundledAttributes[\(attrName)] on '\(collectionNode.name)'")
    }

    /// Apply enumerate pattern (section[].attr) - sets enumeratedAttributes on collection node
    private func applyEnumeratePattern(components: [String], bracketIndex: Int, to root: TreeNode) {
        // Navigate to collection node (components before [])
        let pathToCollection = Array(components[0..<bracketIndex])
        guard let collectionNode = findNode(path: pathToCollection, from: root) else {
            Logger.warning("🎯 [applyEnumeratePattern] Collection not found for path: \(pathToCollection)")
            return
        }

        // Get attribute name (components after [])
        guard bracketIndex + 1 < components.count else {
            Logger.warning("🎯 [applyEnumeratePattern] No attribute after [] in pattern")
            return
        }
        let attrName = components[bracketIndex + 1]

        // Add to enumerated attributes
        var enumerated = collectionNode.enumeratedAttributes ?? []
        if !enumerated.contains(attrName) {
            enumerated.append(attrName)
            collectionNode.enumeratedAttributes = enumerated
        }

        // Note: Don't set .aiToReplace on entries - enumeratedAttributes is the source of truth
        // Visual indicators come from row background color based on enumeratedAttributes

        Logger.info("🎯 [applyEnumeratePattern] Set enumeratedAttributes[\(attrName)] on '\(collectionNode.name)'")
    }

    /// Apply container enumerate pattern (section.container[]) - marks each child of container
    /// Uses enumeratedAttributes with "*" to indicate "enumerate all children"
    private func applyContainerEnumeratePattern(components: [String], to root: TreeNode) {
        // Navigate to container node (all components except final [])
        let pathToContainer = Array(components.dropLast())
        guard let containerNode = findNode(path: pathToContainer, from: root) else {
            Logger.warning("🎯 [applyContainerEnumeratePattern] Container not found for path: \(pathToContainer)")
            return
        }

        // Use enumeratedAttributes with "*" to indicate container enumerate mode
        // This distinguishes from solo (.aiToReplace) for visual indicators
        var enumerated = containerNode.enumeratedAttributes ?? []
        if !enumerated.contains("*") {
            enumerated.append("*")
            containerNode.enumeratedAttributes = enumerated
        }

        Logger.info("🎯 [applyContainerEnumeratePattern] Set enumeratedAttributes[*] on '\(containerNode.name)' for container enumerate")
    }

    /// Apply scalar pattern (section.field) - marks specific node
    private func applyScalarPattern(components: [String], to root: TreeNode) {
        guard let node = findNode(path: components, from: root) else {
            Logger.warning("🎯 [applyScalarPattern] Node not found for path: \(components)")
            return
        }

        node.status = .aiToReplace
        Logger.info("🎯 [applyScalarPattern] Marked scalar '\(node.name)' for AI")
    }

    /// Find a node by navigating a path of component names from root
    private func findNode(path: [String], from root: TreeNode) -> TreeNode? {
        var current = root
        for component in path {
            guard let child = current.findChildByName(component) else {
                let childNames = current.orderedChildren.map { $0.name }
                Logger.debug("🎯 [findNode] Could not find '\(component)' in '\(current.name)'. Available: \(childNames)")
                return nil
            }
            current = child
        }
        Logger.debug("🎯 [findNode] Found node at path: \(path) -> '\(current.name)'")
        return current
    }
}
