//
//  ExperienceDefaultsToTree+Sections.swift
//  Sprung
//
//  Per-section TreeNode builders. Each method creates the section container,
//  iterates items, and adds child field nodes via helpers defined in
//  ExperienceDefaultsToTree.swift.
//

import Foundation

@MainActor
extension ExperienceDefaultsToTree {

    // MARK: - Work Section

    func buildWorkSection(parent: TreeNode) {
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

    func buildVolunteerSection(parent: TreeNode) {
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

    func buildEducationSection(parent: TreeNode) {
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

    func buildProjectsSection(parent: TreeNode) {
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

    func buildSkillsSection(parent: TreeNode) {
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

    func buildAwardsSection(parent: TreeNode) {
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

    func buildCertificatesSection(parent: TreeNode) {
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

    func buildPublicationsSection(parent: TreeNode) {
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

    func buildLanguagesSection(parent: TreeNode) {
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

    func buildInterestsSection(parent: TreeNode) {
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

    func buildReferencesSection(parent: TreeNode) {
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
    func buildCustomSection(parent: TreeNode) {
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

            // Apply manifest descriptor (repeatable, allowsManualMutations, etc.)
            fieldNode.applyDescriptor(manifestField)

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
}
