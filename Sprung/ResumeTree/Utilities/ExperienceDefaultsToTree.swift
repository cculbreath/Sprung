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
        case "summary": return !experienceDefaults.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "work": return experienceDefaults.isWorkEnabled && !experienceDefaults.work.isEmpty
        case "volunteer": return experienceDefaults.isVolunteerEnabled && !experienceDefaults.volunteer.isEmpty
        case "education": return experienceDefaults.isEducationEnabled && !experienceDefaults.education.isEmpty
        case "projects": return experienceDefaults.isProjectsEnabled && !experienceDefaults.projects.isEmpty
        case "skills": return experienceDefaults.isSkillsEnabled && !experienceDefaults.skills.isEmpty
        case "awards": return experienceDefaults.isAwardsEnabled && !experienceDefaults.awards.isEmpty
        case "certificates": return experienceDefaults.isCertificatesEnabled && !experienceDefaults.certificates.isEmpty
        case "publications": return experienceDefaults.isPublicationsEnabled && !experienceDefaults.publications.isEmpty
        case "languages": return experienceDefaults.isLanguagesEnabled && !experienceDefaults.languages.isEmpty
        case "interests": return experienceDefaults.isInterestsEnabled && !experienceDefaults.interests.isEmpty
        case "references": return experienceDefaults.isReferencesEnabled && !experienceDefaults.references.isEmpty
        case "custom": return experienceDefaults.isCustomEnabled && !experienceDefaults.customFields.isEmpty
        default: return true // Allow manifest-defined sections we don't have explicit data for
        }
    }

    private func buildSection(key: String, parent: TreeNode) {
        switch key {
        case "summary":
            buildSummarySection(parent: parent)
        case "work":
            buildWorkSection(parent: parent)
        case "volunteer":
            buildVolunteerSection(parent: parent)
        case "education":
            buildEducationSection(parent: parent)
        case "projects":
            buildProjectsSection(parent: parent)
        case "skills":
            buildSkillsSection(parent: parent)
        case "awards":
            buildAwardsSection(parent: parent)
        case "certificates":
            buildCertificatesSection(parent: parent)
        case "publications":
            buildPublicationsSection(parent: parent)
        case "languages":
            buildLanguagesSection(parent: parent)
        case "interests":
            buildInterestsSection(parent: parent)
        case "references":
            buildReferencesSection(parent: parent)
        case "custom":
            buildCustomSection(parent: parent)
        default:
            break // Unknown section
        }
    }

    // MARK: - Summary Section

    private func buildSummarySection(parent: TreeNode) {
        let summary = experienceDefaults.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }

        let section = manifest.section(for: "summary")
        let node = parent.addChild(TreeNode(
            name: "summary",
            value: summary,
            inEditor: true,
            status: .saved,
            resume: resume
        ))
        applyEditorLabel(to: node, for: "summary")
        if let descriptor = section?.fields.first {
            node.applyDescriptor(descriptor)
        }
    }

    // MARK: - Work Section

    private func buildWorkSection(parent: TreeNode) {
        let section = manifest.section(for: "work")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "work",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "work")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false
        container.schemaAllowsNodeDeletion = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "volunteer")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "volunteer",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "volunteer")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "education")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "education",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "education")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "projects")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "projects",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "projects")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "skills")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "skills",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "skills")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "awards")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "awards",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "awards")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "certificates")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "certificates",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "certificates")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "publications")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "publications",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "publications")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "languages")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "languages",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "languages")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "interests")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "interests",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "interests")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "references")
        let entryDescriptor = section?.fields.first(where: { $0.key == "*" })

        let container = parent.addChild(TreeNode(
            name: "references",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))
        applyEditorLabel(to: container, for: "references")
        container.schemaAllowsChildMutation = entryDescriptor?.allowsManualMutations ?? false

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
        let section = manifest.section(for: "custom")

        // Create custom container for path matching (view flattens it for display)
        let customContainer = parent.addChild(TreeNode(
            name: "custom",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        ))

        for field in experienceDefaults.customFields {
            let fieldNode = customContainer.addChild(TreeNode(
                name: field.key,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            // Try both direct key and custom-prefixed path for editor labels
            applyEditorLabel(to: fieldNode, for: field.key)
            if fieldNode.editorLabel == nil {
                applyEditorLabel(to: fieldNode, for: "custom.\(field.key)")
            }

            // Check if this is an array field or single value
            if field.values.count > 1 || section?.fields.first(where: { $0.key == field.key })?.repeatable == true {
                // Array of values
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
                // Single value - make the field node itself the leaf
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

    private func applyDefaultAIFields(to root: TreeNode, patterns: [String]) {
        Logger.debug("🎯 [applyDefaultAIFields] Starting with \(patterns.count) patterns: \(patterns)")
        applyDefaultAIFieldsRecursive(node: root, currentPath: [], patterns: patterns)
    }

    /// Recursively apply AI status to nodes matching defaultAIFields patterns.
    ///
    /// # Path Syntax
    ///
    /// The path syntax distinguishes between objects (entries with fields) and arrays (simple values):
    ///
    /// - `*` = enumerate objects/entries at this level (e.g., job objects, skill categories)
    /// - `[]` = iterate array values (simple leaf items)
    /// - Plain names = schema field names (e.g., `highlights`, `name`, `keywords`)
    ///
    /// ## Examples
    ///
    /// | Pattern | Meaning |
    /// |---------|---------|
    /// | `work.*` | Each job object |
    /// | `work.*.highlights` | The highlights container for each job |
    /// | `work.*.highlights[]` | Each individual highlight bullet |
    /// | `skills.*` | Each skill category object |
    /// | `skills.*.name` | The name field of each skill category |
    /// | `skills.*.keywords` | Keywords container for each category |
    /// | `skills.*.keywords[]` | Each individual keyword |
    /// | `custom.jobTitles` | Job titles container (all values bundled) |
    /// | `custom.jobTitles[]` | Each job title separately |
    ///
    /// ## Path Building Rules
    ///
    /// When traversing the tree, paths are built as follows:
    /// - Section containers use their name: `work`, `skills`, `custom`
    /// - Object entries (display names like "Acme Corp") use `*`
    /// - Field nodes use their schema name: `highlights`, `keywords`, `name`
    /// - Array leaf items use `[]`
    ///
    private func applyDefaultAIFieldsRecursive(node: TreeNode, currentPath: [String], patterns: [String]) {
        let pathString = currentPath.joined(separator: ".")

        if !pathString.isEmpty {
            let matches = pathMatchesAnyPattern(path: pathString, patterns: patterns)
            if matches {
                Logger.debug("🎯 [applyDefaultAIFields] ✅ MATCH: '\(pathString)' -> setting aiToReplace on '\(node.name)'")
                node.status = .aiToReplace
            } else {
                Logger.verbose("🎯 [applyDefaultAIFields] No match: '\(pathString)' (node: '\(node.name)')")
            }
        }

        guard let children = node.children else { return }
        for child in children {
            var childPath = currentPath

            let isObj = isObjectEntry(child)
            let isArr = isArrayLeafItem(child)

            if isObj {
                // Object entry (e.g., job "Acme Corp", skill category "Programming")
                childPath.append("*")
                Logger.verbose("🎯 [applyDefaultAIFields] Object entry '\(child.name)' -> path component '*'")
            } else if isArr {
                // Array leaf item (e.g., individual keyword, highlight bullet)
                childPath.append("[]")
                Logger.verbose("🎯 [applyDefaultAIFields] Array item '\(child.name)' -> path component '[]'")
            } else {
                // Schema field name (e.g., "highlights", "name", "keywords")
                childPath.append(child.name)
                Logger.verbose("🎯 [applyDefaultAIFields] Schema field '\(child.name)' -> path component '\(child.name)'")
            }
            applyDefaultAIFieldsRecursive(node: child, currentPath: childPath, patterns: patterns)
        }
    }

    /// Check if a node is an object entry (has display name, contains fields)
    /// Object entries are things like job objects ("Acme Corp") or skill categories ("Programming")
    private func isObjectEntry(_ node: TreeNode) -> Bool {
        // Object entries have display names (not lowercase schema names)
        // AND have children (they contain fields)
        guard !isSchemaFieldName(node.name) else { return false }
        return node.children != nil && !node.orderedChildren.isEmpty
    }

    /// Check if a node is an array leaf item (simple value, no children)
    /// Array items are things like individual keywords or highlight bullets
    private func isArrayLeafItem(_ node: TreeNode) -> Bool {
        // Array items have display names (not lowercase schema names)
        // AND are leaf nodes (no children with fields)
        guard !isSchemaFieldName(node.name) else { return false }
        return node.children == nil || node.orderedChildren.isEmpty
    }

    /// Check if a name is a schema field name (lowercase identifier without spaces)
    /// vs a display name like "Acme Corp" or "Work 1"
    private func isSchemaFieldName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        // Schema field names: lowercase, no spaces (e.g., "highlights", "name", "keywords")
        // Display names: uppercase start or contain spaces (e.g., "Acme Corp", "Work 1")
        let startsLowercase = name.first?.isLowercase ?? false
        let hasNoSpaces = !name.contains(" ")
        return startsLowercase && hasNoSpaces
    }

    private func pathMatchesAnyPattern(path: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            pathMatchesPattern(path: path, pattern: pattern)
        }
    }

    /// Match path against pattern.
    ///
    /// Supports:
    /// - `*` matches any object entry (e.g., `work.*` matches `work.*`)
    /// - `[]` matches any array item (e.g., `keywords[]` matches `keywords.[]`)
    ///
    /// Example: pattern `work.*.highlights` matches path `work.*.highlights`
    private func pathMatchesPattern(path: String, pattern: String) -> Bool {
        let pathComponents = path.split(separator: ".").map(String.init)
        let patternComponents = pattern.split(separator: ".").map(String.init)

        guard pathComponents.count == patternComponents.count else { return false }

        for (pathPart, patternPart) in zip(pathComponents, patternComponents) {
            // * matches object entries (which will be * in the path)
            if patternPart == "*" && pathPart == "*" { continue }
            // [] matches array items (which will be [] in the path)
            if patternPart == "[]" && pathPart == "[]" { continue }
            if pathPart != patternPart { return false }
        }
        return true
    }
}
