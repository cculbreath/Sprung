import Foundation
import OrderedCollections

/// Standard resume section identifiers used throughout the template system.
/// Provides type safety for section references and ensures consistency.
enum StandardSection: String, CaseIterable, Codable {
    case summary
    case work
    case volunteer
    case education
    case projects
    case skills
    case awards
    case certificates
    case publications
    case languages
    case interests
    case references
    case custom
    case styling
}

struct TemplateManifestOverrides: Codable {
    struct Styling: Codable {
        var fontSizes: [String: String]?
        var fontSizeOrder: [String]?
        var pageMargins: [String: String]?
        var includeFonts: Bool?
    }
    struct Custom: Codable {
        var sectionLabels: [String: String]?
        var contactLabels: [String: String]?
        var labels: [String: String]?
        var colors: [String: String]?
        var layout: [String: String]?
        var meta: [String: String]?
        var fields: [TemplateManifest.Section.FieldDescriptor]?
        enum CodingKeys: String, CodingKey {
            case sectionLabels
            case contactLabels
            case labels
            case colors
            case layout
            case meta
            case fields
        }
    }
    /// Section-specific overrides (e.g., hiddenFields)
    struct SectionOverride: Codable {
        var type: String?
        var hiddenFields: [String]?
    }
    /// Section order override. Can contain standard sections or custom section names.
    /// Use StandardSection enum for type-safe access to standard sections.
    var sectionOrder: [String]?
    var styling: Styling?
    var custom: Custom?
    var sections: [String: SectionOverride]?
    var sectionVisibility: [String: Bool]?
    var sectionVisibilityLabels: [String: String]?
    var keysInEditor: [String]?
    var editorLabels: [String: String]?
    var defaultAIFields: [String]?
    var listContainers: [String]?
    var reviewPhases: [String: [TemplateManifest.ReviewPhaseConfig]]?

    /// Initialize with type-safe StandardSection array
    init(
        sectionOrder: [StandardSection]? = nil,
        styling: Styling? = nil,
        custom: Custom? = nil,
        sections: [String: SectionOverride]? = nil,
        sectionVisibility: [String: Bool]? = nil,
        sectionVisibilityLabels: [String: String]? = nil,
        keysInEditor: [String]? = nil,
        editorLabels: [String: String]? = nil,
        defaultAIFields: [String]? = nil,
        listContainers: [String]? = nil,
        reviewPhases: [String: [TemplateManifest.ReviewPhaseConfig]]? = nil
    ) {
        self.sectionOrder = sectionOrder?.map(\.rawValue)
        self.styling = styling
        self.custom = custom
        self.sections = sections
        self.sectionVisibility = sectionVisibility
        self.sectionVisibilityLabels = sectionVisibilityLabels
        self.keysInEditor = keysInEditor
        self.editorLabels = editorLabels
        self.defaultAIFields = defaultAIFields
        self.listContainers = listContainers
        self.reviewPhases = reviewPhases
    }
    enum CodingKeys: String, CodingKey {
        case sectionOrder
        case styling
        case custom
        case sections
        case sectionVisibility = "section-visibility"
        case sectionVisibilityLabels = "section-visibility-labels"
        case keysInEditor = "keys-in-editor"
        case editorLabels
        case defaultAIFields
        case listContainers
        case reviewPhases
    }
}
enum TemplateManifestDefaults {
    // MARK: - Public API
    static let defaultSectionOrder: [StandardSection] = [
        .summary,
        .work,
        .volunteer,
        .education,
        .projects,
        .skills,
        .awards,
        .certificates,
        .publications,
        .languages,
        .interests,
        .references,
        .custom,
        .styling
    ]
    static let defaultSectionVisibilityDefaults: [String: Bool] = [
        "work": true,
        "volunteer": true,
        "education": true,
        "projects": true,
        "skills": true,
        "awards": true,
        "certificates": true,
        "publications": true,
        "languages": true,
        "interests": true,
        "references": true
    ]
    static let defaultSectionVisibilityLabels: [String: String] = [
        "work": "Work Experience",
        "volunteer": "Volunteer",
        "education": "Education",
        "projects": "Projects",
        "skills": "Skills",
        "awards": "Awards",
        "certificates": "Certificates",
        "publications": "Publications",
        "languages": "Languages",
        "interests": "Interests",
        "references": "References",
        "meta": "Metadata"
    ]
    // Font sizes scaled by 4/3 for Chrome headless (WKWebView had 4/3 px→pt conversion)
    static let recommendedFontSizes: [String: String] = [
        "boxTitles": "21pt",       // was 16pt
        "contact": "11pt",         // was 8pt
        "degreeNames": "13pt",     // was 10pt
        "employerName": "11pt",    // was 8pt
        "graduationDate": "12pt",  // was 9pt
        "jobTitles": "15pt",       // was 11pt
        "moreInfo": "11pt",        // was 8pt
        "name": "40pt",            // was 30pt
        "projectText": "10pt",     // was 7.5pt
        "schools": "11pt",         // was 8pt
        "sectionTitle": "16pt",    // was 12pt
        "skillDescriptions": "10pt", // was 7.5pt
        "skillNames": "11pt",      // was 8.5pt
        "summary": "12pt",         // was 9pt
        "workDates": "11pt",       // was 8pt
        "workHighlights": "10pt"   // was 7.5pt
    ]
    static let recommendedPageMargins: [String: String] = [
        "top": "0.375in",
        "right": "0.375in",
        "bottom": "0.375in",
        "left": "0.375in"
    ]
    static func baseManifest(for slug: String) -> TemplateManifest {
        TemplateManifest(
            slug: slug,
            schemaVersion: TemplateManifest.currentSchemaVersion,
            sectionOrder: defaultSectionOrder.map(\.rawValue),
            sections: baseSections,
            editorLabels: nil,
            keysInEditor: defaultSectionOrder.map(\.rawValue),
            sectionVisibilityDefaults: defaultSectionVisibilityDefaults,
            sectionVisibilityLabels: defaultSectionVisibilityLabels
        )
    }
    static func manifest(for template: Template) -> TemplateManifest {
        let base = baseManifest(for: template.slug)
        guard let data = template.manifestData, !data.isEmpty else {
            Logger.debug("TemplateManifestDefaults: no overrides for slug \(template.slug), using base manifest")
            return base
        }
        do {
            let overrides = try JSONDecoder().decode(TemplateManifestOverrides.self, from: data)
            Logger.info("🎯 [TemplateManifestDefaults] Decoded overrides for '\(template.slug)': defaultAIFields=\(overrides.defaultAIFields?.description ?? "nil"), listContainers=\(overrides.listContainers?.description ?? "nil"), reviewPhases=\(overrides.reviewPhases?.keys.joined(separator: ",") ?? "nil")")
            return apply(overrides: overrides, to: base, slug: template.slug)
        } catch {
            Logger.warning("TemplateManifestDefaults: Unable to decode manifest overrides for slug \(template.slug): \(error); falling back to defaults.")
            return base
        }
    }
    static func apply(overrides: TemplateManifestOverrides, to base: TemplateManifest, slug: String) -> TemplateManifest {
        var sections = base.sections
        if let stylingOverride = overrides.styling {
            sections["styling"] = sections["styling"]?.applyingStylingOverride(stylingOverride)
        }
        if let customOverride = overrides.custom {
            sections["custom"] = sections["custom"]?.applyingCustomOverride(customOverride)
        }
        // Apply section-specific overrides (hiddenFields, etc.)
        if let sectionOverrides = overrides.sections {
            for (sectionKey, sectionOverride) in sectionOverrides {
                if var existingSection = sections[sectionKey] {
                    existingSection = existingSection.applyingSectionOverride(sectionOverride)
                    sections[sectionKey] = existingSection
                }
            }
        }
        let sectionOrder = overrides.sectionOrder ?? base.sectionOrder
        let sectionVisibilityDefaults = overrides.sectionVisibility ?? base.sectionVisibilityDefaults
        let sectionVisibilityLabels = overrides.sectionVisibilityLabels ?? base.sectionVisibilityLabels
        let keysInEditor = overrides.keysInEditor ?? base.keysInEditor
        let editorLabels = overrides.editorLabels ?? base.editorLabels
        let defaultAIFields = overrides.defaultAIFields ?? base.defaultAIFields
        let listContainers = overrides.listContainers ?? base.listContainers
        let reviewPhases = overrides.reviewPhases ?? base.reviewPhases

        Logger.debug("🎯 [TemplateManifestDefaults.apply] Building manifest with defaultAIFields=\(defaultAIFields?.description ?? "nil")")

        return TemplateManifest(
            slug: slug,
            schemaVersion: TemplateManifest.currentSchemaVersion,
            sectionOrder: sectionOrder,
            sections: sections,
            editorLabels: editorLabels,
            keysInEditor: keysInEditor,
            sectionVisibilityDefaults: sectionVisibilityDefaults,
            sectionVisibilityLabels: sectionVisibilityLabels,
            defaultAIFields: defaultAIFields,
            listContainers: listContainers,
            reviewPhases: reviewPhases
        )
    }
    // MARK: - Base Manifest Construction
    private static let baseSections: [String: TemplateManifest.Section] = {
        var sections: [String: TemplateManifest.Section] = [:]
        sections["basics"] = basicsSection()
        sections["summary"] = summarySection()
        sections["work"] = workSection()
        sections["volunteer"] = volunteerSection()
        sections["education"] = educationSection()
        sections["projects"] = projectsSection()
        sections["skills"] = skillsSection()
        sections["awards"] = awardsSection()
        sections["certificates"] = certificatesSection()
        sections["publications"] = publicationsSection()
        sections["languages"] = languagesSection()
        sections["interests"] = interestsSection()
        sections["references"] = referencesSection()
        sections["custom"] = customSection()
        sections["styling"] = stylingSection()
        return sections
    }()
    // MARK: - Section Builders
    private static func summarySection() -> TemplateManifest.Section {
        // Summary is a single text value (professional summary / objective)
        TemplateManifest.Section(
            type: .string,
            defaultValue: nil,
            fields: [field("summary", input: .textarea)]
        )
    }
    private static func basicsSection() -> TemplateManifest.Section {
        let fields: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true, binding: ["name"]),
            field("label", input: .text, binding: ["label"]),
            field("summary", input: .textarea),
            field("email", input: .email, binding: ["email"]),
            field("phone", input: .phone, binding: ["phone"]),
            field("url", input: .url, binding: ["url"]),
            field("image", input: .text, binding: ["picture"]),
            field("website", input: .url, binding: ["websites"]),
            profilesField()
        ]
        return TemplateManifest.Section(
            type: .object,
            defaultValue: nil,
            fields: fields
        )
    }
    private static func workSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true, title: "Employer"),
            field("position", input: .text),
            field("location", input: .text),
            field("url", input: .url),
            field("startDate", input: .date),
            field("endDate", input: .date),
            field("summary", input: .textarea),
            field("highlights", input: .textarea, repeatable: true, allowsManualMutations: true)
        ]
        return arraySection(children: children, titleTemplate: "{{position}} at {{name}}")
    }
    private static func volunteerSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("organization", input: .text, required: true),
            field("position", input: .text),
            field("url", input: .url),
            field("startDate", input: .date),
            field("endDate", input: .date),
            field("summary", input: .textarea),
            field("highlights", input: .textarea, repeatable: true, allowsManualMutations: true)
        ]
        return arraySection(children: children, titleTemplate: "{{position}} at {{organization}}")
    }
    private static func educationSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("institution", input: .text, required: true),
            field("url", input: .url),
            field("studyType", input: .text),
            field("area", input: .text),
            field("startDate", input: .date),
            field("endDate", input: .date),
            field("score", input: .text),
            field("courses", input: .text, repeatable: true, allowsManualMutations: true)
        ]
        return arraySection(children: children, titleTemplate: "{{area}}")
    }
    private static func projectsSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true),
            field("description", input: .textarea),
            field("highlights", input: .textarea, repeatable: true, allowsManualMutations: true),
            field("keywords", input: .chips, repeatable: true, allowsManualMutations: true),
            field("startDate", input: .date),
            field("endDate", input: .date),
            field("url", input: .url),
            field("roles", input: .chips, repeatable: true, allowsManualMutations: true),
            field("entity", input: .text),
            field("type", input: .text)
        ]
        return arraySection(children: children, titleTemplate: "{{name}}")
    }
    private static func skillsSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true),
            field("level", input: .text),
            field("keywords", input: .chips, repeatable: true, allowsManualMutations: true)
        ]
        return arraySection(children: children, titleTemplate: "{{name}}")
    }
    private static func awardsSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("title", input: .text, required: true),
            field("date", input: .date),
            field("awarder", input: .text),
            field("summary", input: .textarea)
        ]
        return arraySection(children: children, titleTemplate: "{{title}}")
    }
    private static func certificatesSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true),
            field("date", input: .date),
            field("issuer", input: .text),
            field("url", input: .url)
        ]
        return arraySection(children: children, titleTemplate: "{{name}}")
    }
    private static func publicationsSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true),
            field("publisher", input: .text),
            field("releaseDate", input: .date),
            field("url", input: .url),
            field("summary", input: .textarea)
        ]
        return arraySection(children: children, titleTemplate: "{{name}}")
    }
    private static func languagesSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("language", input: .text, required: true),
            field("fluency", input: .text)
        ]
        return arraySection(children: children, titleTemplate: "{{language}}")
    }
    private static func interestsSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true),
            field("keywords", input: .chips, repeatable: true, allowsManualMutations: true)
        ]
        return arraySection(children: children, titleTemplate: "{{name}}")
    }
    private static func referencesSection() -> TemplateManifest.Section {
        let children: [TemplateManifest.Section.FieldDescriptor] = [
            field("name", input: .text, required: true),
            field("reference", input: .textarea),
            field("url", input: .url)
        ]
        return arraySection(children: children, titleTemplate: "{{name}}")
    }
    private static func customSection() -> TemplateManifest.Section {
        TemplateManifest.Section(
            type: .object,
            defaultValue: nil,
            fields: []
        )
    }
    private static func stylingSection() -> TemplateManifest.Section {
        let fields: [TemplateManifest.Section.FieldDescriptor] = [
            mapField("fontSizes"),
            objectField(
                "pageMargins",
                children: [
                    field("top", input: .text),
                    field("right", input: .text),
                    field("bottom", input: .text),
                    field("left", input: .text)
                ]
            ),
            field("includeFonts", input: .toggle, behavior: .includeFonts)
        ]
        let defaultStyling: [String: Any] = [
            "fontSizes": recommendedFontSizes,
            "pageMargins": recommendedPageMargins,
            "includeFonts": true
        ]
        return TemplateManifest.Section(
            type: .object,
            defaultValue: TemplateManifest.JSONValue(value: defaultStyling),
            fields: fields,
            behavior: .styling
        )
    }
    // MARK: - Field Helper Builders
    private static func field(
        _ key: String,
        input: TemplateManifest.Section.FieldDescriptor.InputKind? = nil,
        required: Bool = false,
        repeatable: Bool = false,
        allowsManualMutations: Bool = false,
        behavior: TemplateManifest.Section.FieldDescriptor.Behavior? = nil,
        binding: [String]? = nil,
        placeholder: String? = nil,
        title: String? = nil
    ) -> TemplateManifest.Section.FieldDescriptor {
        TemplateManifest.Section.FieldDescriptor(
            key: key,
            input: input,
            required: required,
            repeatable: repeatable,
            validation: nil,
            titleTemplate: title,
            children: nil,
            placeholder: placeholder,
            behavior: behavior,
            binding: binding.map { TemplateManifest.Section.FieldDescriptor.Binding(source: .applicantProfile, path: $0) },
            allowsManualMutations: allowsManualMutations
        )
    }
    private static func profilesField() -> TemplateManifest.Section.FieldDescriptor {
        TemplateManifest.Section.FieldDescriptor(
            key: "profiles",
            input: nil,
            required: false,
            repeatable: false,
            validation: nil,
            titleTemplate: nil,
            children: [
                TemplateManifest.Section.FieldDescriptor(
                    key: "*",
                    input: nil,
                    required: false,
                    repeatable: true,
                    validation: nil,
                    titleTemplate: "{{network}}",
                    children: [
                        field("network", input: .text),
                        field("username", input: .text),
                        field("url", input: .url)
                    ],
                    placeholder: nil,
                    behavior: nil,
                    binding: nil,
                    allowsManualMutations: true
                )
            ],
            placeholder: nil,
            behavior: nil,
            binding: nil,
            allowsManualMutations: false
        )
    }
    private static func arraySection(children: [TemplateManifest.Section.FieldDescriptor], titleTemplate: String) -> TemplateManifest.Section {
        let arrayDescriptor = TemplateManifest.Section.FieldDescriptor(
            key: "*",
            input: nil,
            required: false,
            repeatable: true,
            validation: nil,
            titleTemplate: titleTemplate,
            children: children,
            placeholder: nil,
            behavior: nil,
            binding: nil,
            allowsManualMutations: true
        )
        return TemplateManifest.Section(
            type: .arrayOfObjects,
            defaultValue: nil,
            fields: [arrayDescriptor]
        )
    }
    private static func objectField(
        _ key: String,
        children: [TemplateManifest.Section.FieldDescriptor]
    ) -> TemplateManifest.Section.FieldDescriptor {
        TemplateManifest.Section.FieldDescriptor(
            key: key,
            input: nil,
            required: false,
            repeatable: false,
            validation: nil,
            titleTemplate: nil,
            children: children,
            placeholder: nil,
            behavior: nil,
            binding: nil,
            allowsManualMutations: false
        )
    }
    private static func mapField(_ key: String) -> TemplateManifest.Section.FieldDescriptor {
        TemplateManifest.Section.FieldDescriptor(
            key: key,
            input: nil,
            required: false,
            repeatable: false,
            validation: nil,
            titleTemplate: nil,
            children: [],
            placeholder: nil,
            behavior: .fontSizes,
            binding: nil,
            allowsManualMutations: false
        )
    }
}
// MARK: - Section Mutation Helpers
private extension TemplateManifest.Section {
    func applyingStylingOverride(_ override: TemplateManifestOverrides.Styling) -> TemplateManifest.Section {
        var dictionary = dictionaryDefaultValue()
        if let fontSizes = override.fontSizes {
            dictionary["fontSizes"] = fontSizes
        }
        if let fontSizeOrder = override.fontSizeOrder {
            dictionary["fontSizeOrder"] = fontSizeOrder
        }
        if let pageMargins = override.pageMargins {
            dictionary["pageMargins"] = pageMargins
        }
        if let includeFonts = override.includeFonts {
            dictionary["includeFonts"] = includeFonts
        }
        return updatingDefault(dictionary)
    }
    func applyingCustomOverride(_ override: TemplateManifestOverrides.Custom) -> TemplateManifest.Section {
        var updated = self
        if let fields = override.fields {
            updated.fields = fields
        }
        var dictionary = dictionaryDefaultValue()
        if let sectionLabels = override.sectionLabels {
            var existing = dictionary["sectionLabels"] as? [String: Any] ?? [:]
            sectionLabels.forEach { existing[$0.key] = $0.value }
            dictionary["sectionLabels"] = existing
        }
        if let contactLabels = override.contactLabels {
            var existing = dictionary["contactLabels"] as? [String: Any] ?? [:]
            contactLabels.forEach { existing[$0.key] = $0.value }
            dictionary["contactLabels"] = existing
        }
        if let labels = override.labels {
            var existing = dictionary["labels"] as? [String: Any] ?? [:]
            labels.forEach { existing[$0.key] = $0.value }
            dictionary["labels"] = existing
        }
        if let colors = override.colors {
            var existing = dictionary["colors"] as? [String: Any] ?? [:]
            colors.forEach { existing[$0.key] = $0.value }
            dictionary["colors"] = existing
        }
        if let layout = override.layout {
            var existing = dictionary["layout"] as? [String: Any] ?? [:]
            layout.forEach { existing[$0.key] = $0.value }
            dictionary["layout"] = existing
        }
        if let meta = override.meta {
            var existing = dictionary["meta"] as? [String: Any] ?? [:]
            meta.forEach { existing[$0.key] = $0.value }
            dictionary["meta"] = existing
        }
        return updated.updatingDefault(dictionary)
    }
    func dictionaryDefaultValue() -> [String: Any] {
        jsonValueToDictionary(defaultValue?.value)
    }
    func updatingDefault(_ dictionary: [String: Any]) -> TemplateManifest.Section {
        TemplateManifest.Section(
            type: type,
            defaultValue: TemplateManifest.JSONValue(value: dictionary),
            fields: fields,
            fieldMetadataSource: fieldMetadataSource,
            behavior: behavior,
            hiddenFields: hiddenFields
        )
    }
    func applyingSectionOverride(_ override: TemplateManifestOverrides.SectionOverride) -> TemplateManifest.Section {
        TemplateManifest.Section(
            type: type,
            defaultValue: defaultValue,
            fields: fields,
            fieldMetadataSource: fieldMetadataSource,
            behavior: behavior,
            hiddenFields: override.hiddenFields ?? hiddenFields
        )
    }
    private func jsonValueToDictionary(_ value: Any?) -> [String: Any] {
        guard let value else { return [:] }
        if let ordered = value as? OrderedDictionary<String, Any> {
            return Dictionary(uniqueKeysWithValues: ordered.map { ($0.key, $0.value) })
        }
        return value as? [String: Any] ?? [:]
    }
}
