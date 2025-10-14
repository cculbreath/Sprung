//
//  ResumeTemplateDataBuilder.swift
//  Sprung
//

import Foundation

/// Builds a Mustache/JSON template context from a `Resume`'s tree representation
/// without manual string concatenation. Replaces the legacy `TreeToJson` helper.
struct ResumeTemplateDataBuilder {
    enum BuilderError: Error {
        case missingRootNode
    }

    static func buildContext(from resume: Resume) throws -> [String: Any] {
        guard let rootNode = resume.rootNode else {
            throw BuilderError.missingRootNode
        }
        let manifest = resume.template.flatMap { TemplateManifestLoader.manifest(for: $0) }
        let implementation = Implementation(resume: resume, rootNode: rootNode, manifest: manifest)
        return implementation.buildContext()
    }
}

// MARK: - Private Implementation

private struct Implementation {
    let resume: Resume
    let rootNode: TreeNode
    let manifest: TemplateManifest?

    func buildContext() -> [String: Any] {
        var context: [String: Any] = [:]

        let orderedKeys = Self.orderedKeys(from: rootNode.orderedChildren.map { $0.name }, manifest: manifest)

        for sectionKey in orderedKeys {
            guard let value = buildSection(named: sectionKey) else { continue }
            context[sectionKey] = value
        }

        // Fallback for editor keys when the node is absent but metadata exists.
        if context["keys-in-editor"] == nil, !resume.importedEditorKeys.isEmpty {
            context["keys-in-editor"] = resume.importedEditorKeys
        }

        return context
    }

    private func buildSection(named sectionName: String) -> Any? {
        if let manifest,
           let behavior = manifest.behavior(forSection: sectionName),
           let override = buildSectionValue(for: behavior, sectionName: sectionName) {
            return override
        }

        if let manifest,
           let section = manifest.section(for: sectionName),
           manifest.isFieldMetadataSynthesized(for: sectionName) == false,
           let value = buildSectionUsingDescriptors(named: sectionName, section: section) {
            return value
        }

        if let manifestKind = manifest?.section(for: sectionName)?.type,
            let sectionType = SectionType(manifestKind: manifestKind) {
            return buildSection(named: sectionName, type: sectionType)
        }

        return nodeValue(named: sectionName)
    }

    private func buildSectionValue(
        for behavior: TemplateManifest.Section.Behavior,
        sectionName: String
    ) -> Any? {
        let sectionNode = sectionNode(named: sectionName)

        switch behavior {
        case .fontSizes:
            if let sectionNode,
               let dictionary = buildNodeValue(sectionNode) {
                let normalized = normalizeValue(dictionary, for: .fontSizes)
                if isEmptyValue(normalized) == false {
                    return normalized
                }
            }
            if let fallback = buildFontSizesSection() {
                return normalizeValue(fallback, for: .fontSizes)
            }
            return nil

        case .includeFonts:
            if let sectionNode,
               let value = buildNodeValue(sectionNode) {
                let normalized = normalizeValue(value, for: .includeFonts)
                if isEmptyValue(normalized) == false {
                    return normalized
                }
            }
            let includeFonts = resume.includeFonts ? "true" : "false"
            return normalizeValue(includeFonts, for: .includeFonts)

        case .editorKeys:
            if let sectionNode,
               let value = buildNodeValue(sectionNode) {
                let normalized = normalizeValue(value, for: .editorKeys)
                if isEmptyValue(normalized) == false {
                    return normalized
                }
            }
            guard resume.importedEditorKeys.isEmpty == false else { return nil }
            return normalizeValue(resume.importedEditorKeys, for: .editorKeys)

        case .styling, .metadata, .applicantProfile:
            return nil
        }
    }

    private func buildSection(named sectionName: String, type: SectionType) -> Any? {
        switch type {
        case .object:
            return buildObjectSection(named: sectionName)
        case .array:
            return buildArraySection(named: sectionName)
        case .complex:
            return buildComplexSection(named: sectionName)
        case .string:
            return buildStringSection(named: sectionName)
        case .mapOfStrings:
            return buildMapOfStringsSection(named: sectionName)
        case .arrayOfObjects:
            return buildArrayOfObjectsSection(named: sectionName)
        case .fontSizes:
            return buildFontSizesSection()
        }
    }

    // MARK: Section Builders

    private func buildObjectSection(named sectionName: String) -> [String: Any]? {
        guard let sectionNode = sectionNode(named: sectionName) else { return nil }
        var result: [String: Any] = [:]

        for child in sectionNode.orderedChildren {
            guard !child.name.isEmpty else { continue }

            if let nested = buildNodeValue(child) {
                result[child.name] = nested
            } else if !child.value.isEmpty {
                result[child.name] = child.value
            }
        }

        return result.isEmpty ? nil : result
    }

    private func buildMapOfStringsSection(named sectionName: String) -> [String: String]? {
        guard let sectionNode = sectionNode(named: sectionName) else { return nil }
        var result: [String: String] = [:]
        for child in sectionNode.orderedChildren {
            let label = resume.keyLabels[child.name] ?? (child.value.isEmpty ? child.name : child.value)
            result[child.name] = label
        }
        return result.isEmpty ? nil : result
    }

    private func buildArraySection(named sectionName: String) -> [Any]? {
        guard let sectionNode = sectionNode(named: sectionName) else { return nil }

        let values = sectionNode.orderedChildren
            .map(\.value)
            .filter { !$0.isEmpty }

        return values.isEmpty ? nil : values
    }

    private func buildStringSection(named sectionName: String) -> Any? {
        guard let sectionNode = sectionNode(named: sectionName) else { return nil }
        guard let firstChild = sectionNode.orderedChildren.first else { return nil }
        let value = firstChild.value
        return value.isEmpty ? nil : value
    }

    private func buildArrayOfObjectsSection(named sectionName: String) -> [Any]? {
        guard let sectionNode = sectionNode(named: sectionName) else { return nil }

        var items: [[String: Any]] = []
        for child in sectionNode.orderedChildren {
            var entry: [String: Any] = [:]
            for grandchild in child.orderedChildren {
                if let nested = buildNodeValue(grandchild) {
                    entry[grandchild.name] = nested
                } else if !grandchild.value.isEmpty {
                    entry[grandchild.name] = grandchild.value
                }
            }

            if entry.isEmpty {
                if !child.value.isEmpty { entry["value"] = child.value }
                if !child.name.isEmpty { entry["title"] = child.name }
            }

            if !entry.isEmpty {
                items.append(entry)
            }
        }

        return items.isEmpty ? nil : items
    }

    private func buildComplexSection(named sectionName: String) -> Any? {
        guard let sectionNode = sectionNode(named: sectionName) else { return nil }
        let children = sectionNode.orderedChildren
        guard !children.isEmpty else { return nil }

        let hasNamedChild = children.contains { !$0.name.isEmpty }

        if hasNamedChild {
            var dictionary: [String: Any] = [:]
            for child in children where !child.name.isEmpty {
                if let value = buildNodeValue(child) {
                    dictionary[child.name] = value
                } else if !child.value.isEmpty {
                    dictionary[child.name] = child.value
                }
            }
            return dictionary.isEmpty ? nil : dictionary
        } else {
            let arrayValues = children.compactMap { node -> Any? in
                if let value = buildNodeValue(node) {
                    return value
                }
                return node.value.isEmpty ? nil : node.value
            }
            return arrayValues.isEmpty ? nil : arrayValues
        }
    }

    private func buildFontSizesSection() -> [String: String]? {
        let sortedNodes = resume.fontSizeNodes.sorted { $0.index < $1.index }
        guard !sortedNodes.isEmpty else { return nil }

        var result: [String: String] = [:]
        for node in sortedNodes {
            result[node.key] = node.fontString
        }
        return result
    }

    // MARK: - Descriptor Helpers

    private func buildSectionUsingDescriptors(
        named sectionName: String,
        section: TemplateManifest.Section
    ) -> Any? {
        let sectionNode = sectionNode(named: sectionName)
        let descriptors = section.fields

        switch section.type {
        case .string:
            guard let descriptor = descriptors.first else {
                return buildStringSection(named: sectionName)
            }
            let valueNode = node(for: descriptor, in: sectionNode)
            return buildValue(for: descriptor, node: valueNode)

        case .array, .arrayOfObjects:
            guard let descriptor = descriptors.first else {
                return buildArraySection(named: sectionName)
            }
            let arrayNode = node(for: descriptor, in: sectionNode)
            return buildValue(for: descriptor, node: arrayNode)

        case .mapOfStrings, .fontSizes:
            guard let sectionNode else { return nil }
            var result: [String: String] = [:]
            for descriptor in descriptors where descriptor.key != "*" {
                let childNode = node(for: descriptor, in: sectionNode)
                if let value = buildValue(for: descriptor, node: childNode) as? String {
                    result[descriptor.key] = value
                }
            }
            return result.isEmpty ? nil : result

        case .object:
            guard let sectionNode else { return nil }
            var result: [String: Any] = [:]
            for descriptor in descriptors where descriptor.key != "*" {
                let childNode = node(for: descriptor, in: sectionNode)
                if let value = buildValue(for: descriptor, node: childNode) {
                    result[descriptor.key] = value
                }
            }
            return result.isEmpty ? nil : result

        case .objectOfObjects:
            guard let sectionNode else { return nil }
            let entryDescriptor = descriptors.first(where: { $0.key == "*" })
            var dictionary: [String: Any] = [:]
            for child in sectionNode.orderedChildren {
                let keyCandidate = (child.schemaSourceKey?.isEmpty == false ? child.schemaSourceKey! : nil)
                    ?? (child.name.isEmpty ? child.value : child.name)
                guard keyCandidate.isEmpty == false else { continue }

                if let entryDescriptor,
                   let children = entryDescriptor.children,
                   !children.isEmpty,
                   var entry = buildObject(using: children, node: child) {
                    decorateEntry(&entry, descriptor: entryDescriptor, key: keyCandidate)
                    dictionary[keyCandidate] = entry
                } else if var entryDict = buildNodeValue(child) as? [String: Any] {
                    decorateEntry(&entryDict, descriptor: entryDescriptor, key: keyCandidate)
                    dictionary[keyCandidate] = entryDict
                } else if let value = buildNodeValue(child) {
                    dictionary[keyCandidate] = value
                }
            }
            if !dictionary.isEmpty {
                return dictionary
            }
            if let entryDescriptor {
                return buildValue(for: entryDescriptor, node: sectionNode)
            }
            return nil
        }
    }

    private func node(
        for descriptor: TemplateManifest.Section.FieldDescriptor,
        in parent: TreeNode?
    ) -> TreeNode? {
        guard let parent else { return nil }
        if descriptor.key == "*" {
            return parent
        }
        if let match = parent.orderedChildren.first(where: { $0.name == descriptor.key }) {
            return match
        }
        if descriptor.key == parent.name {
            return parent.orderedChildren.first
        }
        return nil
    }

    private func buildValue(
        for descriptor: TemplateManifest.Section.FieldDescriptor,
        node: TreeNode?
    ) -> Any? {
        if let bindingValue = resolveBinding(descriptor.binding) {
            return bindingValue
        }

        if descriptor.repeatable {
            if let node {
                if let childrenDescriptors = descriptor.children, !childrenDescriptors.isEmpty {
                    var items: [[String: Any]] = []
                    for (index, child) in node.orderedChildren.enumerated() {
                        if var object = buildObject(using: childrenDescriptors, node: child) {
                            let keyCandidate = resolvedKey(from: child, fallback: "\(index)")
                            decorateEntry(&object, descriptor: descriptor, key: keyCandidate)
                            items.append(object)
                        } else if var dict = buildNodeValue(child) as? [String: Any] {
                            let keyCandidate = resolvedKey(from: child, fallback: "\(index)")
                            decorateEntry(&dict, descriptor: descriptor, key: keyCandidate)
                            items.append(dict)
                        } else if let primitive = buildNodeValue(child) {
                            var wrapper: [String: Any] = ["value": primitive]
                            let keyCandidate = resolvedKey(from: child, fallback: "\(index)")
                            decorateEntry(&wrapper, descriptor: descriptor, key: keyCandidate)
                            items.append(wrapper)
                        }
                    }
                    if items.isEmpty == false {
                        return normalizeValue(items, for: descriptor.behavior)
                    }
                } else {
                    let values = node.orderedChildren
                        .map(\.value)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if values.isEmpty == false {
                        return normalizeValue(values, for: descriptor.behavior)
                    }
                }
            }

            if let behavior = descriptor.behavior {
                return fallbackValue(for: behavior, node: node)
            }
            return nil
        }

        if let childrenDescriptors = descriptor.children, !childrenDescriptors.isEmpty {
            if let node,
               let object = buildObject(using: childrenDescriptors, node: node) {
                return normalizeValue(object, for: descriptor.behavior)
            }

            if let behavior = descriptor.behavior {
                return fallbackValue(for: behavior, node: node)
            }
            return nil
        }

        if let node {
            if node.hasChildren, let nested = buildNodeValue(node) {
                return normalizeValue(nested, for: descriptor.behavior)
            }

            if node.value.isEmpty == false {
                return normalizeValue(node.value, for: descriptor.behavior)
            }
        }

        if let behavior = descriptor.behavior {
            return fallbackValue(for: behavior, node: node)
        }

        return nil
    }

    private func buildObject(
        using descriptors: [TemplateManifest.Section.FieldDescriptor],
        node: TreeNode
    ) -> [String: Any]? {
        var result: [String: Any] = [:]
        for descriptor in descriptors where descriptor.key != "*" {
            let childNode = node.orderedChildren.first(where: { $0.name == descriptor.key })
            if let value = buildValue(for: descriptor, node: childNode) {
                result[descriptor.key] = value
            }
        }

        if result.isEmpty {
            return buildNodeValue(node) as? [String: Any]
        }

        return result
    }

    // MARK: Helpers

    private func resolveBinding(
        _ binding: TemplateManifest.Section.FieldDescriptor.Binding?
    ) -> Any? {
        guard let binding else { return nil }
        switch binding.source {
        case .applicantProfile:
            // Applicant profile binding is resolved when profile data is merged later.
            return nil
        }
    }

    private func fallbackValue(
        for behavior: TemplateManifest.Section.FieldDescriptor.Behavior,
        node: TreeNode?
    ) -> Any? {
        if let node,
           let raw = buildNodeValue(node) {
            let normalized = normalizeValue(raw, for: behavior)
            if isEmptyValue(normalized) == false {
                return normalized
            }
        }

        switch behavior {
        case .fontSizes:
            if let fallback = buildFontSizesSection() {
                return normalizeValue(fallback, for: behavior)
            }
            return nil

        case .includeFonts:
            let includeFonts = resume.includeFonts ? "true" : "false"
            return normalizeValue(includeFonts, for: behavior)

        case .editorKeys:
            guard resume.importedEditorKeys.isEmpty == false else { return nil }
            return normalizeValue(resume.importedEditorKeys, for: behavior)

        case .sectionLabels:
            guard resume.keyLabels.isEmpty == false else { return nil }
            return normalizeValue(resume.keyLabels, for: behavior)

        case .applicantProfile:
            return nil
        }
    }

    private func normalizeValue(
        _ value: Any,
        for behavior: TemplateManifest.Section.FieldDescriptor.Behavior?
    ) -> Any {
        guard let behavior else { return value }

        switch behavior {
        case .includeFonts:
            if let string = value as? String {
                return string
            }
            if let boolValue = value as? Bool {
                return boolValue ? "true" : "false"
            }
            if let number = value as? NSNumber {
                return number.boolValue ? "true" : "false"
            }
            return "\(value)"

        case .fontSizes:
            if let dict = value as? [String: String] {
                return dict
            }
            if let dict = value as? [String: Any] {
                var normalized: [String: String] = [:]
                for (key, anyValue) in dict {
                    if let stringValue = anyValue as? String {
                        normalized[key] = stringValue
                    } else if let number = anyValue as? NSNumber {
                        normalized[key] = "\(number)pt"
                    }
                }
                return normalized
            }
            return value

        case .editorKeys:
            if let strings = value as? [String] {
                return strings
            }
            if let array = value as? [Any] {
                return array.compactMap { element in
                    if let string = element as? String, string.isEmpty == false {
                        return string
                    }
                    return nil
                }
            }
            if let single = value as? String, single.isEmpty == false {
                return [single]
            }
            return value

        case .sectionLabels:
            if let dict = value as? [String: String] {
                return dict
            }
            if let dict = value as? [String: Any] {
                var normalized: [String: String] = [:]
                for (key, anyValue) in dict {
                    if let stringValue = anyValue as? String {
                        normalized[key] = stringValue
                    }
                }
                return normalized
            }
            return value

        case .applicantProfile:
            return value
        }
    }

    private func isEmptyValue(_ value: Any) -> Bool {
        switch value {
        case let string as String:
            return string.isEmpty
        case let strings as [String]:
            return strings.isEmpty
        case let array as [Any]:
            return array.isEmpty
        case let dict as [String: Any]:
            return dict.isEmpty
        case let dict as [String: String]:
            return dict.isEmpty
        default:
            return false
        }
    }

    private func resolvedKey(from node: TreeNode, fallback: String) -> String {
        if let source = node.schemaSourceKey, source.isEmpty == false {
            return source
        }
        if node.name.isEmpty == false {
            return node.name
        }
        if node.value.isEmpty == false {
            return node.value
        }
        return fallback
    }

    private func decorateEntry(
        _ entry: inout [String: Any],
        descriptor: TemplateManifest.Section.FieldDescriptor?,
        key: String
    ) {
        guard key.isEmpty == false else { return }

        if entry["__key"] == nil {
            entry["__key"] = key
        }

        guard let descriptor else { return }

        if let template = descriptor.titleTemplate {
            for placeholder in TitleRenderer.placeholders(in: template) {
                guard entry[placeholder] == nil else { continue }
                if ["employer", "company", "school", "institution"].contains(placeholder) {
                    entry[placeholder] = key
                }
            }
        }

        var titleContext = entry
        if titleContext["__key"] == nil {
            titleContext["__key"] = key
        }

        var meta: [String: Any] = [:]
        if let template = descriptor.titleTemplate,
           let computed = TitleRenderer.render(template, context: titleContext) {
            meta["title"] = computed
        }

        let validation = validationResult(for: entry, descriptor: descriptor)
        if descriptor.required || descriptor.validation != nil || validation.isValid == false {
            meta["isValid"] = validation.isValid
            if let message = validation.messages.first, message.isEmpty == false {
                meta["message"] = message
            }
        }

        if meta.isEmpty == false {
            meta["key"] = key
            entry["__meta"] = meta
        }
    }

    private struct ValidationResult {
        let isValid: Bool
        let messages: [String]

        static let valid = ValidationResult(isValid: true, messages: [])

        func merging(_ other: ValidationResult) -> ValidationResult {
            ValidationResult(
                isValid: isValid && other.isValid,
                messages: messages + other.messages
            )
        }
    }

    private func validationResult(
        for value: Any?,
        descriptor: TemplateManifest.Section.FieldDescriptor
    ) -> ValidationResult {
        if descriptor.repeatable {
            guard let array = value as? [Any], array.isEmpty == false else {
                if descriptor.required {
                    let message = descriptor.validation?.message ?? "At least one value is required."
                    return ValidationResult(isValid: false, messages: [message])
                }
                return .valid
            }

            if let childDescriptor = descriptor.children?.first {
                return array.reduce(.valid) { partial, element in
                    partial.merging(validationResult(for: element, descriptor: childDescriptor))
                }
            } else {
                return array.reduce(.valid) { partial, element in
                    let string = stringValue(from: element) ?? ""
                    return partial.merging(evaluateLeafValue(string, descriptor: descriptor))
                }
            }
        }

        if let children = descriptor.children, children.isEmpty == false {
            guard let dict = value as? [String: Any] else {
                if descriptor.required {
                    let message = descriptor.validation?.message ?? "Missing required values."
                    return ValidationResult(isValid: false, messages: [message])
                }
                return .valid
            }

            return children.reduce(.valid) { partial, childDescriptor in
                let childValue = dict[childDescriptor.key]
                return partial.merging(validationResult(for: childValue, descriptor: childDescriptor))
            }
        }

        let string = stringValue(from: value) ?? ""
        return evaluateLeafValue(string, descriptor: descriptor)
    }

    private func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case let dict as [String: Any]:
            return dict["value"] as? String
        default:
            return nil
        }
    }

    private func evaluateLeafValue(
        _ value: String,
        descriptor: TemplateManifest.Section.FieldDescriptor
    ) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if descriptor.required && trimmed.isEmpty {
            let message = descriptor.validation?.message ?? "This field is required."
            return ValidationResult(isValid: false, messages: [message])
        }

        guard let validation = descriptor.validation, trimmed.isEmpty == false else {
            return .valid
        }

        let message = validation.message ?? defaultMessage(for: validation.rule)
        switch validation.rule {
        case .regex:
            if let pattern = validation.pattern,
               let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .email:
            let pattern = validation.pattern ?? "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .url:
            guard let url = URL(string: trimmed), url.scheme != nil else {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .phone:
            let pattern = validation.pattern ?? "^[0-9+()\\-\\s]{7,}$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .minLength:
            if let min = validation.min, Double(trimmed.count) < min {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .maxLength:
            if let max = validation.max, Double(trimmed.count) > max {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .lengthRange:
            if let min = validation.min, Double(trimmed.count) < min {
                return ValidationResult(isValid: false, messages: [message])
            }
            if let max = validation.max, Double(trimmed.count) > max {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .enumeration:
            let options = validation.options ?? []
            if options.isEmpty == false &&
                options.contains(where: { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) == false {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .numericRange:
            guard let number = Double(trimmed) else {
                return ValidationResult(isValid: false, messages: [message])
            }
            if let min = validation.min, number < min {
                return ValidationResult(isValid: false, messages: [message])
            }
            if let max = validation.max, number > max {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .custom:
            break
        }

        return .valid
    }

    private func defaultMessage(
        for rule: TemplateManifest.Section.FieldDescriptor.Validation.Rule
    ) -> String {
        switch rule {
        case .regex, .custom:
            return "Value does not match the expected format."
        case .email:
            return "Enter a valid email address."
        case .url:
            return "Enter a valid URL."
        case .phone:
            return "Enter a valid phone number."
        case .minLength:
            return "Value is too short."
        case .maxLength:
            return "Value is too long."
        case .lengthRange:
            return "Value is not within the allowed length."
        case .enumeration:
            return "Value must match one of the allowed options."
        case .numericRange:
            return "Value is outside the allowed range."
        }
    }

    private enum TitleRenderer {
        static func placeholders(in template: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+)\\s*\\}\\}") else {
                return []
            }

            let matches = regex.matches(
                in: template,
                range: NSRange(template.startIndex..., in: template)
            )

            return matches.compactMap { match in
                guard match.numberOfRanges >= 2,
                      let range = Range(match.range(at: 1), in: template) else {
                    return nil
                }
                let raw = template[range].trimmingCharacters(in: .whitespacesAndNewlines)
                guard raw.contains(".") == false else { return nil }
                return raw
            }
        }

        static func render(_ template: String, context: [String: Any]) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+)\\s*\\}\\}") else {
                return nil
            }
            var result = template
            let matches = regex.matches(
                in: template,
                range: NSRange(template.startIndex..., in: template)
            )
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let range = Range(match.range(at: 1), in: template) else { continue }
                let keyPath = template[range].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let replacement = lookupValue(forKeyPath: keyPath, context: context),
                      replacement.isEmpty == false else {
                    return nil
                }
                if let fullRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullRange, with: replacement)
                }
            }
            return result
        }

        private static func lookupValue(
            forKeyPath keyPath: String,
            context: [String: Any]
        ) -> String? {
            let components = keyPath.split(separator: ".").map(String.init)
            var current: Any? = context
            for component in components {
                if let dict = current as? [String: Any] {
                    current = dict[component]
                } else {
                    current = nil
                }
            }
            if let string = current as? String {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let number = current as? NSNumber {
                return number.stringValue
            }
            return nil
        }
    }

    private func sectionNode(named name: String) -> TreeNode? {
        rootNode.children?.first(where: { $0.name == name })
    }

    private func nodeValue(named sectionName: String) -> Any? {
        guard let node = sectionNode(named: sectionName) else { return nil }
        if node.orderedChildren.isEmpty {
            return node.value.isEmpty ? nil : node.value
        }
        return buildNodeValue(node)
    }

    private func buildNodeValue(_ node: TreeNode) -> Any? {
        let children = node.orderedChildren
        if children.isEmpty {
            return node.value.isEmpty ? nil : node.value
        }

        var dictionary: [String: Any] = [:]
        var arrayElements: [Any] = []
        var sawArrayElement = false

        for child in children {
            if child.hasChildren {
                guard let nested = buildNodeValue(child) else { continue }
                if child.name.isEmpty {
                    sawArrayElement = true
                    arrayElements.append(nested)
                } else {
                    dictionary[child.name] = nested
                }
            } else if child.name.isEmpty {
                sawArrayElement = true
                if !child.value.isEmpty {
                    arrayElements.append(child.value)
                }
            } else if !child.value.isEmpty {
                dictionary[child.name] = child.value
            }
        }

        if sawArrayElement && dictionary.isEmpty {
            return arrayElements.isEmpty ? nil : arrayElements
        }
        return dictionary.isEmpty ? nil : dictionary
    }

    private static func orderedKeys(from keys: [String], manifest: TemplateManifest?) -> [String] {
        guard let manifest else { return keys }
        var ordered: [String] = []
        for key in manifest.sectionOrder where keys.contains(key) {
            ordered.append(key)
        }
        for key in keys where !ordered.contains(key) {
            ordered.append(key)
        }
        return ordered
    }
}
