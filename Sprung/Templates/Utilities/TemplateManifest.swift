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

            private enum CodingKeys: String, CodingKey {
                case key
                case input
                case required
                case repeatable
                case validation
                case titleTemplate
                case children
                case placeholder
            }

            init(
                key: String,
                input: InputKind? = nil,
                required: Bool = false,
                repeatable: Bool = false,
                validation: Validation? = nil,
                titleTemplate: String? = nil,
                children: [FieldDescriptor]? = nil,
                placeholder: String? = nil
            ) {
                self.key = key
                self.input = input
                self.required = required
                self.repeatable = repeatable
                self.validation = validation
                self.titleTemplate = titleTemplate
                self.children = children
                self.placeholder = placeholder
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
            }
        }

        enum FieldMetadataSource {
            case declared
            case synthesized
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case defaultValue = "default"
            case fields
        }

        let type: Kind
        let defaultValue: JSONValue?
        var fields: [FieldDescriptor]
        var fieldMetadataSource: FieldMetadataSource

        init(
            type: Kind,
            defaultValue: JSONValue?,
            fields: [FieldDescriptor] = [],
            fieldMetadataSource: FieldMetadataSource = .declared
        ) {
            self.type = type
            self.defaultValue = defaultValue
            self.fields = fields
            self.fieldMetadataSource = fieldMetadataSource
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(Kind.self, forKey: .type)
            defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .defaultValue)
            fields = try container.decodeIfPresent([FieldDescriptor].self, forKey: .fields) ?? []
            fieldMetadataSource = fields.isEmpty ? .synthesized : .declared
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
            if !fields.isEmpty {
                try container.encode(fields, forKey: .fields)
            }
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

    static let currentSchemaVersion: Int = 2

    let slug: String
    let schemaVersion: Int
    let sectionOrder: [String]
    private(set) var sections: [String: Section]
    private(set) var synthesizedSectionKeys: Set<String>

    var usesSynthesizedMetadata: Bool {
        !synthesizedSectionKeys.isEmpty
    }

    init(
        slug: String,
        schemaVersion: Int = 1,
        sectionOrder: [String],
        sections: [String: Section]
    ) {
        self.slug = slug
        self.schemaVersion = schemaVersion
        self.sectionOrder = sectionOrder
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
        try container.encode(sections, forKey: .sections)
    }

    func section(for key: String) -> Section? {
        sections[key]
    }

    func isFieldMetadataSynthesized(for key: String) -> Bool {
        synthesizedSectionKeys.contains(key)
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
    }
}

// MARK: - Encoding helpers

extension TemplateManifest {
    func upgradingSchemaVersionIfNeeded() -> TemplateManifest {
        guard schemaVersion < Self.currentSchemaVersion else { return self }
        return TemplateManifest(
            slug: slug,
            schemaVersion: Self.currentSchemaVersion,
            sectionOrder: sectionOrder,
            sections: sections
        )
    }

    func encode(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> TemplateManifest {
        try JSONDecoder().decode(TemplateManifest.self, from: data)
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
