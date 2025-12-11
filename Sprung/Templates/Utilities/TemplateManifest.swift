import Foundation
import OrderedCollections
struct TemplateManifest: Codable {
    struct Section: Codable {
        enum Kind: String, Codable {
            case string
            case array
            case object
            case mapOfStrings
            case objectOfObjects
            case arrayOfObjects
            case fontSizes
        }
        enum Behavior: String, Codable {
            case styling
            case fontSizes
            case includeFonts
            case editorKeys
            case applicantProfile
            case metadata
        }
        struct FieldDescriptor: Codable {
            enum InputKind: String, Codable {
                case text
                case textarea
                case markdown
                case chips
                case date
                case toggle
                case number
                case url
                case email
                case phone
                case select
            }
            enum Behavior: String, Codable {
                case fontSizes
                case includeFonts
                case editorKeys
                case sectionLabels
                case applicantProfile
            }
            enum BindingSource: String, Codable {
                case applicantProfile
            }
            struct Binding: Codable {
                let source: BindingSource
                let path: [String]
                init(source: BindingSource, path: [String]) {
                    self.source = source
                    self.path = path
                }
                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let stringValue = try? container.decode(String.self) {
                        let components = stringValue.split(separator: ".").map(String.init)
                        guard let first = components.first,
                              let resolvedSource = BindingSource(rawValue: first) else {
                            throw DecodingError.dataCorruptedError(
                                in: container,
                                debugDescription: "Invalid binding string '\(stringValue)'"
                            )
                        }
                        source = resolvedSource
                        path = Array(components.dropFirst())
                        return
                    }
                    let keyed = try decoder.container(keyedBy: CodingKeys.self)
                    let rawSource = try keyed.decode(String.self, forKey: .source)
                    guard let resolvedSource = BindingSource(rawValue: rawSource) else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .source,
                            in: keyed,
                            debugDescription: "Unsupported binding source '\(rawSource)'"
                        )
                    }
                    source = resolvedSource
                    path = try keyed.decodeIfPresent([String].self, forKey: .path) ?? []
                }
                func encode(to encoder: Encoder) throws {
                    if path.isEmpty {
                        var container = encoder.singleValueContainer()
                        try container.encode(source.rawValue)
                        return
                    }
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(source.rawValue, forKey: .source)
                    try container.encode(path, forKey: .path)
                }
                private enum CodingKeys: String, CodingKey {
                    case source
                    case path
                }
            }
            private enum CodingKeys: String, CodingKey {
                case key
                case input
                case required
                case repeatable
                case validation
            case titleTemplate
            case children
            case placeholder
            case behavior
            case binding
            case allowsManualMutations
        }
        struct Validation: Codable {
            enum Rule: String, Codable {
                case regex
                    case email
                    case url
                    case phone
                    case minLength
                    case maxLength
                    case lengthRange
                    case enumeration
                    case numericRange
                    case custom
                }
                let rule: Rule
                let pattern: String?
                let min: Double?
                let max: Double?
                let options: [String]?
                let message: String?
            }
            let key: String
            let input: InputKind?
            let required: Bool
            let repeatable: Bool
            let validation: Validation?
            let titleTemplate: String?
            let children: [FieldDescriptor]?
            let placeholder: String?
            let behavior: Behavior?
            let binding: Binding?
            let allowsManualMutations: Bool
            init(
                key: String,
                input: InputKind? = nil,
                required: Bool = false,
                repeatable: Bool = false,
                validation: Validation? = nil,
                titleTemplate: String? = nil,
                children: [FieldDescriptor]? = nil,
                placeholder: String? = nil,
                behavior: Behavior? = nil,
                binding: Binding? = nil,
                allowsManualMutations: Bool = false
            ) {
                self.key = key
                self.input = input
                self.required = required
                self.repeatable = repeatable
                self.validation = validation
                self.titleTemplate = titleTemplate
                self.children = children
                self.placeholder = placeholder
                self.behavior = behavior
                self.binding = binding
                self.allowsManualMutations = allowsManualMutations
            }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                key = try container.decode(String.self, forKey: .key)
                input = try container.decodeIfPresent(InputKind.self, forKey: .input)
                required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
                repeatable = try container.decodeIfPresent(Bool.self, forKey: .repeatable) ?? false
                validation = try container.decodeIfPresent(Validation.self, forKey: .validation)
                titleTemplate = try container.decodeIfPresent(String.self, forKey: .titleTemplate)
                children = try container.decodeIfPresent([FieldDescriptor].self, forKey: .children)
                placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
                behavior = try container.decodeIfPresent(Behavior.self, forKey: .behavior)
                binding = try container.decodeIfPresent(Binding.self, forKey: .binding)
                allowsManualMutations = try container.decodeIfPresent(Bool.self, forKey: .allowsManualMutations) ?? false
            }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(key, forKey: .key)
                try container.encodeIfPresent(input, forKey: .input)
                if required {
                    try container.encode(required, forKey: .required)
                }
                if repeatable {
                    try container.encode(repeatable, forKey: .repeatable)
                }
                try container.encodeIfPresent(validation, forKey: .validation)
                try container.encodeIfPresent(titleTemplate, forKey: .titleTemplate)
                try container.encodeIfPresent(children, forKey: .children)
                try container.encodeIfPresent(placeholder, forKey: .placeholder)
                try container.encodeIfPresent(behavior, forKey: .behavior)
                try container.encodeIfPresent(binding, forKey: .binding)
                if allowsManualMutations {
                    try container.encode(allowsManualMutations, forKey: .allowsManualMutations)
                }
            }
        }
        /// Tracks whether section metadata was declared in the manifest or
        /// synthesized at runtime for legacy templates (schema < v2024.09).
        enum FieldMetadataSource {
            case declared
            case synthesized
        }
        private enum CodingKeys: String, CodingKey {
            case type
            case defaultValue = "default"
            case fields
            case behavior
            case hiddenFields
        }
        let type: Kind
        let defaultValue: JSONValue?
        var fields: [FieldDescriptor]
        var fieldMetadataSource: FieldMetadataSource
        let behavior: Behavior?
        /// Keys to hide from the tree editor. Use for fields the template doesn't render.
        /// For example, if a template uses `highlights` but not `description`, add `"description"`
        /// to hide it from the editor. Supports nested paths like `"custom.location"`.
        let hiddenFields: [String]?
        init(
            type: Kind,
            defaultValue: JSONValue?,
            fields: [FieldDescriptor] = [],
            fieldMetadataSource: FieldMetadataSource = .declared,
            behavior: Behavior? = nil,
            hiddenFields: [String]? = nil
        ) {
            self.type = type
            self.defaultValue = defaultValue
            self.fields = fields
            self.fieldMetadataSource = fieldMetadataSource
            self.behavior = behavior
            self.hiddenFields = hiddenFields
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(Kind.self, forKey: .type)
            defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .defaultValue)
            fields = try container.decodeIfPresent([FieldDescriptor].self, forKey: .fields) ?? []
            fieldMetadataSource = fields.isEmpty ? .synthesized : .declared
            behavior = try container.decodeIfPresent(Behavior.self, forKey: .behavior)
            hiddenFields = try container.decodeIfPresent([String].self, forKey: .hiddenFields)
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
            if !fields.isEmpty {
                try container.encode(fields, forKey: .fields)
            }
            try container.encodeIfPresent(behavior, forKey: .behavior)
            try container.encodeIfPresent(hiddenFields, forKey: .hiddenFields)
        }
        mutating func ensureFieldDescriptors(for sectionKey: String) {
            guard fields.isEmpty else { return }
            let synthesized = FieldDescriptorFactory.descriptors(
                forSectionKey: sectionKey,
                kind: type,
                defaultValue: defaultValue?.value
            )
            fields = synthesized
            fieldMetadataSource = .synthesized
            Logger.debug(
                "TemplateManifest: synthesized field descriptors for section \(sectionKey)"
            )
        }
        func defaultContextValue() -> Any? {
            guard let value = defaultValue?.value else { return nil }
            switch type {
            case .mapOfStrings, .fontSizes:
                if let dict = value as? [String: Any] {
                    var result: [String: String] = [:]
                    for (key, inner) in dict {
                        if let stringValue = inner as? String {
                            result[key] = stringValue
                        }
                    }
                    return result
                }
                if let ordered = value as? OrderedDictionary<String, Any> {
                    var result: [String: String] = [:]
                    for (key, inner) in ordered {
                        if let stringValue = inner as? String {
                            result[key] = stringValue
                        }
                    }
                    return result
                }
                return nil
            default:
                return TemplateManifest.normalize(value)
            }
        }
    }
    struct JSONValue: Codable {
        let value: Any
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                value = NSNull()
            } else if let dict = try? container.decode([String: JSONValue].self) {
                value = OrderedDictionary(uniqueKeysWithValues: dict.map { ($0.key, $0.value.value) })
            } else if let array = try? container.decode([JSONValue].self) {
                value = array.map(\.value)
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let int = try? container.decode(Int.self) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = double
            } else {
                throw DecodingError.typeMismatch(
                    Any.self,
                    .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
                )
            }
        }
        init(value: Any) {
            self.value = value
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case is NSNull:
                try container.encodeNil()
            case let string as String:
                try container.encode(string)
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    try container.encode(number.boolValue)
                } else if number.doubleValue.rounded() == number.doubleValue {
                    try container.encode(number.intValue)
                } else {
                    try container.encode(number.doubleValue)
                }
            case let dict as [String: Any]:
                let encoded = dict.reduce(into: [String: JSONValue]()) { partialResult, element in
                    partialResult[element.key] = JSONValue(value: element.value)
                }
                try container.encode(encoded)
            case let ordered as OrderedDictionary<String, Any>:
                let encoded = ordered.reduce(into: [String: JSONValue]()) { partialResult, element in
                    partialResult[element.key] = JSONValue(value: element.value)
                }
                try container.encode(encoded)
            case let array as [Any]:
                let encoded = array.map { JSONValue(value: $0) }
                try container.encode(encoded)
            default:
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Unsupported JSON value: \(type(of: value))"
                    )
                )
            }
        }
    }
    static let currentSchemaVersion: Int = 4
    let slug: String
    let schemaVersion: Int
    let sectionOrder: [String]
    private(set) var sections: [String: Section]
    private(set) var synthesizedSectionKeys: Set<String>
    let editorLabels: [String: String]?
    let keysInEditor: [String]?
    let sectionVisibilityDefaults: [String: Bool]?
    let sectionVisibilityLabels: [String: String]?

    // MARK: - AI Revision Configuration

    /// Field paths to pre-select for AI revision when creating new resumes.
    ///
    /// # Path Syntax
    ///
    /// - `*` = enumerate objects/entries (e.g., job objects, skill categories)
    /// - `[]` = iterate array values (simple leaf items)
    /// - Plain names = schema field names
    ///
    /// ## Examples
    /// - `work.*.highlights` - highlights container for each job (bundled)
    /// - `skills.*.name` - name field of each skill category
    /// - `custom.jobTitles[]` - each individual job title
    let defaultAIFields: [String]?

    /// Paths that contain array data reviewed as batches (not individual nodes).
    /// Uses the same path syntax as defaultAIFields.
    let listContainers: [String]?

    /// Multi-phase review configuration for sections requiring structured review workflows.
    /// Key is section name (e.g., "skills"), value is array of phase configs.
    ///
    /// ## Example
    /// ```json
    /// "reviewPhases": {
    ///   "skills": [
    ///     { "phase": 1, "field": "skills.*.name", "bundle": true },
    ///     { "phase": 2, "field": "skills.*.keywords", "bundle": false }
    ///   ]
    /// }
    /// ```
    let reviewPhases: [String: [ReviewPhaseConfig]]?

    /// Configuration for a single review phase
    struct ReviewPhaseConfig: Codable {
        /// Phase number (1-indexed, executed in order)
        let phase: Int
        /// Field path to review in this phase (uses path syntax)
        let field: String
        /// If true, all matching nodes are bundled into a single review unit.
        /// If false (default), each matching node is reviewed separately.
        let bundle: Bool

        init(phase: Int, field: String, bundle: Bool = false) {
            self.phase = phase
            self.field = field
            self.bundle = bundle
        }

        private enum CodingKeys: String, CodingKey {
            case phase, field, bundle
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            phase = try container.decode(Int.self, forKey: .phase)
            field = try container.decode(String.self, forKey: .field)
            bundle = try container.decodeIfPresent(Bool.self, forKey: .bundle) ?? false
        }
    }

    init(
        slug: String,
        schemaVersion: Int = 1,
        sectionOrder: [String],
        sections: [String: Section],
        editorLabels: [String: String]? = nil,
        keysInEditor: [String]? = nil,
        sectionVisibilityDefaults: [String: Bool]? = nil,
        sectionVisibilityLabels: [String: String]? = nil,
        defaultAIFields: [String]? = nil,
        listContainers: [String]? = nil,
        reviewPhases: [String: [ReviewPhaseConfig]]? = nil
    ) {
        self.slug = slug
        self.schemaVersion = schemaVersion
        self.sectionOrder = sectionOrder
        self.editorLabels = editorLabels
        self.keysInEditor = keysInEditor
        self.sectionVisibilityDefaults = sectionVisibilityDefaults
        self.sectionVisibilityLabels = sectionVisibilityLabels
        self.defaultAIFields = defaultAIFields
        self.listContainers = listContainers
        self.reviewPhases = reviewPhases
        var normalized: [String: Section] = [:]
        var synthesized: Set<String> = []
        for (key, var section) in sections {
            section.ensureFieldDescriptors(for: key)
            if section.fieldMetadataSource == .synthesized {
                synthesized.insert(key)
            }
            normalized[key] = section
        }
        self.sections = normalized
        synthesizedSectionKeys = synthesized
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sectionOrder = try container.decodeIfPresent([String].self, forKey: .sectionOrder) ?? []
        editorLabels = try container.decodeIfPresent([String: String].self, forKey: .editorLabels)
        keysInEditor = try container.decodeIfPresent([String].self, forKey: .keysInEditor)
        sectionVisibilityDefaults = try container.decodeIfPresent([String: Bool].self, forKey: .sectionVisibilityDefaults)
        sectionVisibilityLabels = try container.decodeIfPresent([String: String].self, forKey: .sectionVisibilityLabels)
        defaultAIFields = try container.decodeIfPresent([String].self, forKey: .defaultAIFields)
        listContainers = try container.decodeIfPresent([String].self, forKey: .listContainers)
        reviewPhases = try container.decodeIfPresent([String: [ReviewPhaseConfig]].self, forKey: .reviewPhases)
        let decodedSections = try container.decode([String: Section].self, forKey: .sections)
        var normalized: [String: Section] = [:]
        var synthesized: Set<String> = []
        for (key, var section) in decodedSections {
            section.ensureFieldDescriptors(for: key)
            if section.fieldMetadataSource == .synthesized {
                synthesized.insert(key)
            }
            normalized[key] = section
        }
        sections = normalized
        synthesizedSectionKeys = synthesized
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        if !sectionOrder.isEmpty {
            try container.encode(sectionOrder, forKey: .sectionOrder)
        }
        try container.encodeIfPresent(editorLabels, forKey: .editorLabels)
        try container.encodeIfPresent(keysInEditor, forKey: .keysInEditor)
        try container.encodeIfPresent(sectionVisibilityDefaults, forKey: .sectionVisibilityDefaults)
        try container.encodeIfPresent(sectionVisibilityLabels, forKey: .sectionVisibilityLabels)
        try container.encodeIfPresent(defaultAIFields, forKey: .defaultAIFields)
        try container.encodeIfPresent(listContainers, forKey: .listContainers)
        try container.encodeIfPresent(reviewPhases, forKey: .reviewPhases)
        try container.encode(sections, forKey: .sections)
    }
    func section(for key: String) -> Section? {
        sections[key]
    }
    func behavior(forSection key: String) -> Section.Behavior? {
        sections[key]?.behavior
    }
    func isFieldMetadataSynthesized(for key: String) -> Bool {
        synthesizedSectionKeys.contains(key)
    }
    func customFieldKeyPaths() -> Set<String> {
        guard let customSection = sections["custom"] else { return [] }
        var results: Set<String> = []
        collectCustomFieldPaths(
            in: customSection.fields,
            currentPath: ["custom"],
            accumulator: &results
        )
        return results
    }
    private func collectCustomFieldPaths(
        in descriptors: [Section.FieldDescriptor],
        currentPath: [String],
        accumulator: inout Set<String>
    ) {
        for descriptor in descriptors {
            if descriptor.key == "*" {
                if let children = descriptor.children, children.isEmpty == false {
                    collectCustomFieldPaths(
                        in: children,
                        currentPath: currentPath,
                        accumulator: &accumulator
                    )
                } else {
                    accumulator.insert(currentPath.joined(separator: "."))
                }
                continue
            }
            let nextPath = currentPath + [descriptor.key]
            if let children = descriptor.children, children.isEmpty == false {
                collectCustomFieldPaths(
                    in: children,
                    currentPath: nextPath,
                    accumulator: &accumulator
                )
            } else {
                accumulator.insert(nextPath.joined(separator: "."))
            }
        }
    }
    func makeDefaultContext() -> [String: Any] {
        var context: [String: Any] = [:]
        for key in sectionOrder {
            if let value = sections[key]?.defaultContextValue() {
                context[key] = value
            }
        }
        return context
    }
    static func normalize(_ value: Any) -> Any {
        switch value {
        case is NSNull:
            return NSNull()
        case let ordered as OrderedDictionary<String, Any>:
            var dict: [String: Any] = [:]
            for (key, inner) in ordered {
                dict[key] = normalize(inner)
            }
            return dict
        case let dict as [String: Any]:
            var normalized: [String: Any] = [:]
            for (key, inner) in dict {
                normalized[key] = normalize(inner)
            }
            return normalized
        case let array as [Any]:
            return array.map { normalize($0) }
        default:
            return value
        }
    }
    private enum CodingKeys: String, CodingKey {
        case slug
        case schemaVersion
        case sectionOrder
        case sections
        case editorLabels
        case keysInEditor = "keys-in-editor"
        case sectionVisibilityDefaults = "section-visibility"
        case sectionVisibilityLabels = "section-visibility-labels"
        case defaultAIFields
        case listContainers
        case reviewPhases
    }
}
// MARK: - Encoding helpers
extension TemplateManifest {
    func sectionVisibilityKeys() -> [String] {
        guard let defaultKeys = sectionVisibilityDefaults?.keys else { return [] }
        return Array(defaultKeys).sorted()
    }
}

// MARK: - AI Revision Configuration Helpers
extension TemplateManifest {
    /// Check if a tree path matches any of the defaultAIFields patterns
    /// - Parameter path: Tree path like "skills.0.keywords.2" or "work.1.highlights"
    /// - Returns: true if this path should be pre-selected for AI revision
    func isDefaultAIField(path: String) -> Bool {
        guard let patterns = defaultAIFields else { return false }
        return patterns.contains { pattern in
            pathMatchesPattern(path: path, pattern: pattern)
        }
    }

    /// Check if a tree path is a list container (should be reviewed as batch)
    /// - Parameter path: Tree path like "skills.0.keywords" or "work.1.highlights"
    /// - Returns: true if this path should use batch review
    func isListContainer(path: String) -> Bool {
        guard let patterns = listContainers else { return false }
        return patterns.contains { pattern in
            pathMatchesPattern(path: path, pattern: pattern)
        }
    }

    /// Get review phases for a section
    /// - Parameter section: Section name like "skills"
    /// - Returns: Array of ReviewPhaseConfig sorted by phase number, or nil if no phases defined
    func reviewPhasesConfig(for section: String) -> [ReviewPhaseConfig]? {
        guard let phases = reviewPhases?[section], !phases.isEmpty else {
            return nil
        }
        return phases.sorted { $0.phase < $1.phase }
    }

    /// Match a concrete path against a glob pattern
    /// Pattern "work.*.highlights" matches "work.0.highlights", "work.1.highlights", etc.
    /// - Parameters:
    ///   - path: Concrete path with numeric indices
    ///   - pattern: Glob pattern with * wildcards
    /// - Returns: true if path matches pattern
    private func pathMatchesPattern(path: String, pattern: String) -> Bool {
        let pathComponents = path.split(separator: ".").map(String.init)
        let patternComponents = pattern.split(separator: ".").map(String.init)

        guard pathComponents.count == patternComponents.count else {
            return false
        }

        for (pathPart, patternPart) in zip(pathComponents, patternComponents) {
            if patternPart == "*" {
                // Wildcard matches any single component (typically a numeric index)
                continue
            }
            if pathPart != patternPart {
                return false
            }
        }
        return true
    }
}
// MARK: - Field Descriptor Synthesis
private enum FieldDescriptorFactory {
    static func descriptors(
        forSectionKey sectionKey: String,
        kind: TemplateManifest.Section.Kind,
        defaultValue: Any?
    ) -> [TemplateManifest.Section.FieldDescriptor] {
        switch kind {
        case .string:
            return [
                TemplateManifest.Section.FieldDescriptor(
                    key: sectionKey,
                    input: .text
                )
            ]
        case .array:
            return [
                TemplateManifest.Section.FieldDescriptor(
                    key: sectionKey,
                    input: .chips,
                    repeatable: true
                )
            ]
        case .mapOfStrings, .fontSizes:
            guard let dict = asOrderedDictionary(defaultValue) else {
                return []
            }
            return dict.map { key, value in
                TemplateManifest.Section.FieldDescriptor(
                    key: key,
                    input: .text,
                    required: false,
                    repeatable: false,
                    children: childDescriptors(from: value)
                )
            }
        case .object:
            guard let dict = asOrderedDictionary(defaultValue) else {
                return []
            }
            return dict.map { key, value in
                TemplateManifest.Section.FieldDescriptor(
                    key: key,
                    input: inputKind(for: value),
                    children: childDescriptors(from: value)
                )
            }
        case .objectOfObjects:
            if let dict = asOrderedDictionary(defaultValue),
               let sample = dict.values.first {
                let children = childDescriptors(from: sample) ?? []
                return [
                    TemplateManifest.Section.FieldDescriptor(
                        key: sectionKey,
                        input: nil,
                        repeatable: true,
                        children: children
                    )
                ]
            }
            return [
                TemplateManifest.Section.FieldDescriptor(
                    key: sectionKey,
                    input: nil,
                    repeatable: true
                )
            ]
        case .arrayOfObjects:
            if let array = defaultValue as? [Any],
               let sample = array.first {
                let children = childDescriptors(from: sample) ?? []
                return [
                    TemplateManifest.Section.FieldDescriptor(
                        key: sectionKey,
                        input: nil,
                        repeatable: true,
                        children: children
                    )
                ]
            }
            return [
                TemplateManifest.Section.FieldDescriptor(
                    key: sectionKey,
                    input: nil,
                    repeatable: true
                )
            ]
        }
    }
    private static func childDescriptors(from value: Any) -> [TemplateManifest.Section.FieldDescriptor]? {
        if let dict = asOrderedDictionary(value) {
            return dict.map { key, inner in
                TemplateManifest.Section.FieldDescriptor(
                    key: key,
                    input: inputKind(for: inner),
                    repeatable: isRepeatable(inner),
                    children: childDescriptors(from: inner)
                )
            }
        }
        if let array = value as? [Any], let first = array.first {
            if let dict = asOrderedDictionary(first) {
                let children = dict.map { key, inner in
                    TemplateManifest.Section.FieldDescriptor(
                        key: key,
                        input: inputKind(for: inner),
                        children: childDescriptors(from: inner)
                    )
                }
                return [
                    TemplateManifest.Section.FieldDescriptor(
                        key: "items",
                        input: nil,
                        repeatable: true,
                        children: children
                    )
                ]
            }
            return [
                TemplateManifest.Section.FieldDescriptor(
                    key: "items",
                    input: inputKind(for: first),
                    repeatable: true
                )
            ]
        }
        return nil
    }
    private static func asOrderedDictionary(_ value: Any?) -> OrderedDictionary<String, Any>? {
        if let ordered = value as? OrderedDictionary<String, Any> {
            return ordered
        }
        if let dict = value as? [String: Any] {
            return OrderedDictionary(uniqueKeysWithValues: dict.map { ($0.key, $0.value) })
        }
        return nil
    }
    private static func isRepeatable(_ value: Any) -> Bool {
        value is [Any]
    }
    private static func inputKind(for value: Any) -> TemplateManifest.Section.FieldDescriptor.InputKind {
        switch value {
        case is Bool:
            return .toggle
        case let string as String:
            return string.contains("\n") ? .textarea : .text
        case is Int, is Double, is NSNumber:
            return .number
        case is [Any]:
            return .chips
        default:
            return .text
        }
    }
}
