//
//  JsonToTree.swift
//  Sprung
//
//  Rewritten to separate data-tree construction from view concerns.
//
import Foundation
import OrderedCollections
/// Builds the mutable `TreeNode` hierarchy that powers the resume editor.
/// Requires a manifest and uses it as the single source of truth for ordering,
/// visibility, and behaviour.
final class JsonToTree {
    fileprivate let resume: Resume
    fileprivate let manifest: TemplateManifest?
    fileprivate let orderedContext: OrderedDictionary<String, Any>
    fileprivate let originalContext: [String: Any]
    fileprivate let sectionKeys: [String]
    fileprivate var indexCounter: Int = 0
    private init(
        resume: Resume,
        orderedContext: OrderedDictionary<String, Any>,
        manifest: TemplateManifest?,
        originalContext: [String: Any],
        orderedKeys: [String]
    ) {
        self.resume = resume
        self.orderedContext = orderedContext
        self.manifest = manifest
        self.originalContext = originalContext
        sectionKeys = orderedKeys
    }
    convenience init(resume: Resume, context: [String: Any], manifest: TemplateManifest?) {
        let (orderedContext, orderedKeys) = JsonToTree.makeOrderedContext(from: context, manifest: manifest)
        self.init(
            resume: resume,
            orderedContext: orderedContext,
            manifest: manifest,
            originalContext: context,
            orderedKeys: orderedKeys
        )
    }
    func buildTree() -> TreeNode? {
        guard resume.needToTree else { return resume.rootNode }
        resume.needToTree = false
        guard let manifest else {
            Logger.error("JsonToTree: missing manifest for template \(resume.template?.slug ?? "unknown"); aborting tree build.")
            resume.needToTree = true
            return nil
        }
        resetResumeState()
        let renderer = ManifestRenderer(host: self, manifest: manifest)
        guard let root = renderer.build() else { return nil }
        root.rebuildViewHierarchy(manifest: manifest)
        return root
    }
}
// MARK: - Shared helpers -----------------------------------------------------
private extension JsonToTree {
    static func makeOrderedContext(
        from context: [String: Any],
        manifest: TemplateManifest?
    ) -> (OrderedDictionary<String, Any>, [String]) {
        var ordered: OrderedDictionary<String, Any> = [:]
        // Include manifest-declared editor keys so sections like `custom` appear even
        // when the source context omits them.
        let manifestRootKeys = editorRootKeys(from: manifest)
        let preferredOrder = orderedKeys(from: Array(context.keys) + manifestRootKeys, manifest: manifest)
        for key in preferredOrder {
            if let value = context[key] {
                ordered[key] = convertToOrderedStructure(value)
            } else if let placeholder = placeholderValue(for: key, manifest: manifest) {
                ordered[key] = placeholder
            }
        }
        let extraKeys = context.keys.filter { ordered[$0] == nil }.sorted()
        for key in extraKeys {
            ordered[key] = convertToOrderedStructure(context[key] as Any)
        }
        return (ordered, Array(ordered.keys))
    }
    static func convertToOrderedStructure(_ value: Any) -> Any {
        if let ordered = value as? OrderedDictionary<String, Any> { return ordered }
        if let dict = value as? [String: Any] {
            var ordered: OrderedDictionary<String, Any> = [:]
            for (key, inner) in dict {
                ordered[key] = convertToOrderedStructure(inner)
            }
            return ordered
        }
        if let array = value as? [Any] {
            return array.map { convertToOrderedStructure($0) }
        }
        return value
    }
    static func orderedKeys(from keys: [String], manifest: TemplateManifest?) -> [String] {
        guard let manifest else { return keys.sorted() }
        var ordered: [String] = []
        for key in manifest.sectionOrder where keys.contains(key) {
            ordered.append(key)
        }
        for key in keys where ordered.contains(key) == false {
            ordered.append(key)
        }
        return ordered
    }
    static func editorRootKeys(from manifest: TemplateManifest?) -> [String] {
        guard let keys = manifest?.keysInEditor else { return [] }
        return keys.compactMap { $0.split(separator: ".").first }.map(String.init)
    }
    static func placeholderValue(for key: String, manifest: TemplateManifest?) -> Any? {
        guard let manifest, let section = manifest.section(for: key) else { return nil }
        if let defaultValue = section.defaultContextValue() {
            return defaultValue
        }
        switch section.type {
        case .array, .arrayOfObjects:
            return []
        case .mapOfStrings, .objectOfObjects, .fontSizes:
            return [:]
        case .string:
            return ""
        case .object:
            return placeholderObject(for: section)
        }
    }
    static func placeholderObject(for section: TemplateManifest.Section) -> OrderedDictionary<String, Any> {
        var placeholder: OrderedDictionary<String, Any> = [:]
        for field in section.fields where field.key != "*" {
            placeholder[field.key] = placeholderValue(for: field)
        }
        return placeholder
    }
    static func placeholderValue(for field: TemplateManifest.Section.FieldDescriptor) -> Any {
        if let behavior = field.behavior {
            switch behavior {
            case .fontSizes:
                return [:]
            case .includeFonts:
                return false
            case .editorKeys:
                return []
            case .sectionLabels:
                return [:]
            case .applicantProfile:
                return ""
            }
        }
        if let children = field.children, children.isEmpty == false {
            var nested: OrderedDictionary<String, Any> = [:]
            for child in children where child.key != "*" {
                nested[child.key] = placeholderValue(for: child)
            }
            return nested
        }
        if field.repeatable {
            return []
        }
        if field.input == .toggle {
            return false
        }
        return ""
    }
    func value(for key: String) -> Any? {
        if let stored = orderedContext[key] { return stored }
        guard let original = originalContext[key] else { return nil }
        return JsonToTree.convertToOrderedStructure(original)
    }
    func resetResumeState() {
        if resume.needToFont {
            resume.fontSizeNodes = []
        }
        resume.includeFonts = false
        resume.importedEditorKeys = []
        resume.keyLabels = [:]
    }
    func assignFontSizes(from value: Any?) {
        guard resume.needToFont else { return }
        guard let value,
              let orderedFonts = orderedDictionary(from: value) else {
            return
        }
        resume.needToFont = false
        var nodes: [FontSizeNode] = []
        for (key, rawValue) in orderedFonts {
            let fontString: String
            if let stringValue = rawValue as? String {
                fontString = stringValue
            } else if let numberValue = rawValue as? NSNumber {
                fontString = "\(numberValue.stringValue)pt"
            } else {
                fontString = String(describing: rawValue)
            }
            let node = FontSizeNode(
                key: key,
                index: indexCounter,
                fontString: fontString,
                resume: resume
            )
            indexCounter += 1
            nodes.append(node)
        }
        resume.fontSizeNodes = nodes
    }
    func assignIncludeFonts(from value: Any?) {
        guard let value else { return }
        if let boolValue = value as? Bool {
            resume.includeFonts = boolValue
        } else if let stringValue = value as? String {
            resume.includeFonts = (stringValue as NSString).boolValue
        } else if let numberValue = value as? NSNumber {
            resume.includeFonts = numberValue.boolValue
        }
    }
    func assignEditorKeys(from value: Any?) {
        guard let value else { return }
        if let strings = value as? [String] {
            resume.importedEditorKeys = strings
        } else if let array = value as? [Any] {
            resume.importedEditorKeys = array.compactMap { $0 as? String }
        } else if let single = value as? String {
            resume.importedEditorKeys = [single]
        }
    }
    func assignSectionLabels(from value: Any?) {
        guard let value else { return }
        var labels: [String: String] = [:]
        if let dict = value as? [String: String] {
            labels = dict
        } else if let dict = value as? [String: Any] {
            for (key, anyValue) in dict {
                if let stringValue = anyValue as? String {
                    labels[key] = stringValue
                }
            }
        } else if let ordered = value as? OrderedDictionary<String, Any> {
            for (key, anyValue) in ordered {
                if let stringValue = anyValue as? String {
                    labels[key] = stringValue
                }
            }
        }
        guard labels.isEmpty == false else { return }
        for (key, label) in labels {
            resume.keyLabels[key] = label
        }
    }
    func orderedDictionary(from value: Any) -> OrderedDictionary<String, Any>? {
        if let ordered = value as? OrderedDictionary<String, Any> { return ordered }
        if let dict = value as? [String: Any] {
            var ordered: OrderedDictionary<String, Any> = [:]
            for (key, inner) in dict {
                ordered[key] = JsonToTree.convertToOrderedStructure(inner)
            }
            return ordered
        }
        return nil
    }
}
// MARK: - Manifest-driven renderer ------------------------------------------
private final class ManifestRenderer {
    private unowned let host: JsonToTree
    private let manifest: TemplateManifest
    private let editorLabels: [String: String]
    /// Pre-computed set of hidden field paths for quick lookup.
    /// Includes both direct keys and full paths from each section's hiddenFields.
    private var hiddenFieldPaths: Set<String> = []
    init(host: JsonToTree, manifest: TemplateManifest) {
        self.host = host
        self.manifest = manifest
        editorLabels = manifest.editorLabels ?? [:]
        buildHiddenFieldPaths()
    }
    private func buildHiddenFieldPaths() {
        for (sectionKey, section) in manifest.sections {
            guard let hidden = section.hiddenFields else { continue }
            for field in hidden {
                // Store the full path (e.g., "work.description") for lookup
                hiddenFieldPaths.insert("\(sectionKey).\(field)")
            }
        }
    }
    /// Checks if a field at the given path should be hidden from the editor.
    private func isFieldHidden(path: [String]) -> Bool {
        guard path.count >= 2 else { return false }
        // For paths like ["work", "0", "description"], extract section and field
        let sectionKey = path[0]
        // Get the last component as the field name
        guard let fieldName = path.last else { return false }
        // Check if this specific field is hidden for this section
        return hiddenFieldPaths.contains("\(sectionKey).\(fieldName)")
    }
    func build() -> TreeNode? {
        host.applyManifestBehaviors(using: manifest)
        let root = TreeNode(
            name: "root",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: host.resume
        )
        for key in host.sectionKeys where shouldIncludeSection(key) {
            guard let rawValue = host.value(for: key) else { continue }
            buildSection(
                name: key,
                value: rawValue,
                descriptor: manifest.section(for: key),
                parent: root,
                path: [key]
            )
        }
        return root
    }
    private func shouldIncludeSection(_ key: String) -> Bool {
        // Skip basics - profile data comes fresh from ApplicantProfile at render time
        if key == "basics" {
            return false
        }
        if let behavior = manifest.behavior(forSection: key),
           [.styling, .includeFonts, .editorKeys, .metadata].contains(behavior) {
            return false
        }
        return true
    }
    private func buildSection(
        name: String,
        value: Any,
        descriptor: TemplateManifest.Section?,
        parent: TreeNode,
        path: [String]
    ) {
        guard let kind = descriptor?.type ?? inferKind(from: value) else { return }
        switch kind {
        case .string:
            buildStringLeaf(
                name: name,
                value: value,
                descriptor: descriptor?.fields.first,
                parent: parent,
                path: path
            )
        case .array:
            buildArray(
                name: name,
                value: value,
                descriptor: descriptor?.fields.first,
                parent: parent,
                path: path
            )
        case .mapOfStrings:
            buildMapOfStrings(
                name: name,
                value: value,
                descriptor: descriptor,
                parent: parent,
                path: path
            )
        case .arrayOfObjects:
            buildArrayOfObjects(
                name: name,
                value: value,
                descriptor: descriptor,
                parent: parent,
                path: path
            )
        case .object, .objectOfObjects:
            buildObject(
                name: name,
                value: value,
                descriptor: descriptor,
                parent: parent,
                path: path
            )
        case .fontSizes:
            // Handled via behaviour; omit from tree.
            break
        }
    }
    private func buildStringLeaf(
        name: String,
        value: Any,
        descriptor: TemplateManifest.Section.FieldDescriptor?,
        parent: TreeNode,
        path: [String]
    ) {
        guard let stringValue = value as? String else { return }
        let node = parent.addChild(
            TreeNode(
                name: name,
                value: stringValue,
                inEditor: true,
                status: .saved,
                resume: host.resume
            )
        )
        node.applyDescriptor(descriptor)
        applyEditorLabel(path: path, to: node)
    }
    private func buildArray(
        name: String,
        value: Any,
        descriptor: TemplateManifest.Section.FieldDescriptor?,
        parent: TreeNode,
        path: [String]
    ) {
        let elements: [Any]
        if let anyArray = value as? [Any] {
            elements = anyArray
        } else if let stringArray = value as? [String] {
            elements = stringArray.map { $0 as Any }
        } else {
            return
        }
        let container = parent.addChild(
            TreeNode(
                name: name,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: host.resume
            )
        )
        container.schemaAllowsChildMutation = descriptor?.allowsManualMutations ?? false
        applyEditorLabel(path: path, to: container)
        if elements.allSatisfy({ $0 is String }) {
            for (index, stringValue) in elements.enumerated() {
                guard let stringValue = stringValue as? String else { continue }
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else { continue }
                let child = container.addChild(
                    TreeNode(
                        name: "",
                        value: trimmed,
                        inEditor: true,
                        status: .saved,
                        resume: host.resume
                    )
                )
                child.applyDescriptor(descriptor)
                // Leaf entries for simple arrays should not be treated as containers.
                child.schemaAllowsChildMutation = false
                applyEditorLabel(path: path + ["\(index)"], to: child)
            }
            return
        }
        for (index, element) in elements.enumerated() {
            let childPath = path + ["\(index)"]
            if let dictValue = element as? OrderedDictionary<String, Any> {
                let child = container.addChild(
                    TreeNode(
                        name: "",
                        value: "",
                        inEditor: true,
                        status: .isNotLeaf,
                        resume: host.resume
                    )
                )
                child.applyDescriptor(descriptor)
                applyEditorLabel(path: childPath, to: child)
                buildObjectFields(
                    dictionary: dictValue,
                    descriptors: descriptor?.children,
                    parent: child,
                    path: childPath
                )
                continue
            }
            if let dictValue = element as? [String: Any] {
                guard let ordered = host.orderedDictionary(from: dictValue) else { continue }
                let child = container.addChild(
                    TreeNode(
                        name: "",
                        value: "",
                        inEditor: true,
                        status: .isNotLeaf,
                        resume: host.resume
                    )
                )
                child.applyDescriptor(descriptor)
                applyEditorLabel(path: childPath, to: child)
                buildObjectFields(
                    dictionary: ordered,
                    descriptors: descriptor?.children,
                    parent: child,
                    path: childPath
                )
                continue
            }
            if let stringValue = element as? String {
                let child = container.addChild(
                    TreeNode(
                        name: "",
                        value: stringValue,
                        inEditor: true,
                        status: .saved,
                        resume: host.resume
                    )
                )
                child.applyDescriptor(descriptor)
                applyEditorLabel(path: childPath, to: child)
            }
        }
    }
    private func buildMapOfStrings(
        name: String,
        value: Any,
        descriptor: TemplateManifest.Section?,
        parent: TreeNode,
        path: [String]
    ) {
        guard let dict = host.orderedDictionary(from: value) else { return }
        let container = parent.addChild(
            TreeNode(
                name: name,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: host.resume
            )
        )
        applyEditorLabel(path: path, to: container)
        let orderedKeys = orderedKeys(in: dict, descriptors: descriptor?.fields)
        for key in orderedKeys {
            guard let rawValue = dict[key] as? String else { continue }
            host.resume.keyLabels[key] = rawValue
            let child = container.addChild(
                TreeNode(
                    name: key,
                    value: rawValue,
                    inEditor: true,
                    status: .saved,
                    resume: host.resume
                )
            )
            let childDescriptor = descriptorField(for: key, in: descriptor?.fields)
            child.applyDescriptor(childDescriptor)
            applyEditorLabel(path: path + [key], to: child)
        }
    }
    private func buildArrayOfObjects(
        name: String,
        value: Any,
        descriptor: TemplateManifest.Section?,
        parent: TreeNode,
        path: [String]
    ) {
        guard let entryDescriptor = descriptor?.fields.first(where: { $0.key == "*" }) else {
            buildObject(name: name, value: value, descriptor: descriptor, parent: parent, path: path)
            return
        }
        guard let normalizedEntries = normalizedArrayEntries(
            value: value,
            entryDescriptor: entryDescriptor
        ) else {
            return
        }
        let container = parent.addChild(
            TreeNode(
                name: name,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: host.resume
            )
        )
        container.schemaAllowsChildMutation = entryDescriptor.allowsManualMutations
        container.schemaAllowsNodeDeletion = entryDescriptor.allowsManualMutations
        applyEditorLabel(path: path, to: container)
        for (index, entry) in normalizedEntries.enumerated() {
            let title = displayTitle(
                fallback: "\(name.capitalized) \(index + 1)",
                descriptor: entryDescriptor,
                element: entry.value
            )
            let childPath = path + ["\(index)"]
            let child = container.addChild(
                TreeNode(
                    name: title,
                    value: "",
                    inEditor: true,
                    status: .isNotLeaf,
                    resume: host.resume
                )
            )
            child.schemaSourceKey = entry.sourceKey
            child.applyDescriptor(entryDescriptor)
            applyEditorLabel(path: childPath, to: child)
            buildObjectFields(
                dictionary: entry.value,
                descriptors: entryDescriptor.children,
                parent: child,
                path: childPath
            )
        }
    }
    private func buildObject(
        name: String,
        value: Any,
        descriptor: TemplateManifest.Section?,
        parent: TreeNode,
        path: [String]
    ) {
        guard let dict = host.orderedDictionary(from: value) else { return }
        let container = parent.addChild(
            TreeNode(
                name: name,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: host.resume
            )
        )
        applyEditorLabel(path: path, to: container)
        buildObjectFields(
            dictionary: dict,
            descriptors: descriptor?.fields,
            parent: container,
            path: path
        )
    }
    private func buildObjectFields(
        dictionary: OrderedDictionary<String, Any>,
        descriptors: [TemplateManifest.Section.FieldDescriptor]?,
        parent: TreeNode,
        path: [String]
    ) {
        let orderedKeys = orderedKeys(in: dictionary, descriptors: descriptors)
        for key in orderedKeys {
            guard let rawValue = dictionary[key] else { continue }
            let fieldPath = path + [key]
            // Skip hidden fields (template doesn't use this field)
            if isFieldHidden(path: fieldPath) {
                continue
            }
            guard let descriptor = descriptorField(for: key, in: descriptors) else { continue }
            if descriptor.binding?.source == .applicantProfile {
                continue
            }
            if let behavior = descriptor.behavior {
                handleBehavior(behavior, value: rawValue)
                continue
            }
            switch rawValue {
            case let stringValue as String:
                let child = parent.addChild(
                    TreeNode(
                        name: key,
                        value: stringValue,
                        inEditor: true,
                        status: .saved,
                        resume: host.resume
                    )
                )
                child.applyDescriptor(descriptor)
                applyEditorLabel(path: fieldPath, to: child)
            case let dictValue as OrderedDictionary<String, Any>:
                buildChildObject(
                    name: key,
                    dictionary: dictValue,
                    descriptor: descriptor,
                    parent: parent,
                    path: fieldPath
                )
            case let dictValue as [String: Any]:
                guard let ordered = host.orderedDictionary(from: dictValue) else { continue }
                buildChildObject(
                    name: key,
                    dictionary: ordered,
                    descriptor: descriptor,
                    parent: parent,
                    path: fieldPath
                )
            case _ where rawValue is [Any] || rawValue is [String]:
                buildArray(
                    name: key,
                    value: rawValue,
                    descriptor: descriptor,
                    parent: parent,
                    path: fieldPath
                )
            default:
                continue
            }
        }
    }
    private func buildChildObject(
        name: String,
        dictionary: OrderedDictionary<String, Any>,
        descriptor: TemplateManifest.Section.FieldDescriptor,
        parent: TreeNode,
        path: [String]
    ) {
        let child = parent.addChild(
            TreeNode(
                name: name,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: host.resume
            )
        )
        child.schemaAllowsChildMutation = descriptor.allowsManualMutations
        child.applyDescriptor(descriptor)
        applyEditorLabel(path: path, to: child)
        buildObjectFields(
            dictionary: dictionary,
            descriptors: descriptor.children,
            parent: child,
            path: path
        )
    }
    private func applyEditorLabel(path: [String], to node: TreeNode) {
        guard let tail = path.last else { return }
        if let label = editorLabels[path.joined(separator: ".")] {
            node.editorLabel = label
        } else if let label = editorLabels[tail] {
            node.editorLabel = label
        }
    }
    private func orderedKeys(
        in dict: OrderedDictionary<String, Any>,
        descriptors: [TemplateManifest.Section.FieldDescriptor]?
    ) -> [String] {
        guard let descriptors, descriptors.isEmpty == false else {
            return Array(dict.keys)
        }
        var keys: [String] = []
        for descriptor in descriptors where descriptor.key != "*" {
            if dict.keys.contains(descriptor.key) {
                keys.append(descriptor.key)
            }
        }
        for key in dict.keys where keys.contains(key) == false {
            keys.append(key)
        }
        return keys
    }
    private func descriptorField(
        for key: String,
        in descriptors: [TemplateManifest.Section.FieldDescriptor]?
    ) -> TemplateManifest.Section.FieldDescriptor? {
        guard let descriptors else { return nil }
        if let exact = descriptors.first(where: { $0.key == key }) { return exact }
        return descriptors.first(where: { $0.key == "*" })
    }
    private func handleBehavior(
        _ behavior: TemplateManifest.Section.FieldDescriptor.Behavior,
        value: Any
    ) {
        switch behavior {
        case .fontSizes:
            host.assignFontSizes(from: value)
        case .includeFonts:
            host.assignIncludeFonts(from: value)
        case .editorKeys:
            host.assignEditorKeys(from: value)
        case .sectionLabels:
            host.assignSectionLabels(from: value)
        case .applicantProfile:
            break
        }
    }
    private func inferKind(from value: Any) -> TemplateManifest.Section.Kind? {
        switch value {
        case is String:
            return .string
        case is [String]:
            return .array
        case let dict as OrderedDictionary<String, Any>:
            if dict.values.allSatisfy({ $0 is String }) { return .mapOfStrings }
            if dict.values.allSatisfy({ $0 is OrderedDictionary<String, Any> }) { return .objectOfObjects }
            return .object
        case let dict as [String: Any]:
            if dict.values.allSatisfy({ $0 is String }) { return .mapOfStrings }
            if dict.values.allSatisfy({ $0 is [String: Any] }) { return .objectOfObjects }
            return .object
        case let array as [Any]:
            if array.allSatisfy({ $0 is String }) { return .array }
            if array.allSatisfy({ $0 is OrderedDictionary<String, Any> || $0 is [String: Any] }) {
                return .arrayOfObjects
            }
            return .array
        default:
            return nil
        }
    }
    private func normalizedArrayEntries(
        value: Any,
        entryDescriptor: TemplateManifest.Section.FieldDescriptor
    ) -> [ArrayEntry]? {
        if let ordered = value as? [OrderedDictionary<String, Any>] {
            return ordered.map { ArrayEntry(sourceKey: nil, value: $0) }
        }
        if let array = value as? [[String: Any]] {
            return array.compactMap { dict in
                guard let ordered = host.orderedDictionary(from: dict) else { return nil }
                return ArrayEntry(sourceKey: nil, value: ordered)
            }
        }
        if let dict = host.orderedDictionary(from: value) {
            var result: [ArrayEntry] = []
            for (key, rawValue) in dict {
                if let entryDict = rawValue as? OrderedDictionary<String, Any> {
                    result.append(ArrayEntry(sourceKey: key, value: entryDict))
                    continue
                }
                if let stringValue = rawValue as? String {
                    var entry: OrderedDictionary<String, Any> = [:]
                    assignTitleAndPrimaryValue(
                        to: &entry,
                        title: key,
                        value: stringValue,
                        descriptor: entryDescriptor
                    )
                    result.append(ArrayEntry(sourceKey: key, value: entry))
                    continue
                }
            }
            return result.isEmpty ? nil : result
        }
        if let array = value as? [String] {
            return array.map {
                ArrayEntry(
                    sourceKey: nil,
                    value: ["title": $0]
                )
            }
        }
        return nil
    }
    private func assignTitleAndPrimaryValue(
        to entry: inout OrderedDictionary<String, Any>,
        title: String,
        value: String,
        descriptor: TemplateManifest.Section.FieldDescriptor
    ) {
        if let children = descriptor.children, children.isEmpty == false {
            let titleDescriptor = children.first(where: { $0.key == "title" }) ?? children.first
            if let titleDescriptor {
                entry[titleDescriptor.key] = title
            }
            if let valueDescriptor = children.first(where: { $0.key != titleDescriptor?.key }) {
                entry[valueDescriptor.key] = value
            }
        } else {
            entry["title"] = title
            entry["value"] = value
        }
    }
    private func displayTitle(
        fallback: String,
        descriptor: TemplateManifest.Section.FieldDescriptor,
        element: OrderedDictionary<String, Any>
    ) -> String {
        if let template = descriptor.titleTemplate,
           let rendered = renderTemplate(template, using: element) {
            return rendered
        }
        let preferredKeys = ["title", "name", "position", "employer"]
        for key in preferredKeys {
            if let stringValue = element[key] as? String, stringValue.isEmpty == false {
                return stringValue
            }
        }
        for value in element.values {
            if let stringValue = value as? String, stringValue.isEmpty == false {
                return stringValue
            }
        }
        return fallback
    }
    private func renderTemplate(
        _ template: String,
        using element: OrderedDictionary<String, Any>
    ) -> String? {
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
            let key = String(template[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let replacement = element[key] as? String,
                  replacement.isEmpty == false else {
                return nil
            }
            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }
    private struct ArrayEntry {
        let sourceKey: String?
        let value: OrderedDictionary<String, Any>
    }
}
// MARK: - Manifest behaviours ------------------------------------------------
private extension JsonToTree {
    func applyManifestBehaviors(using manifest: TemplateManifest) {
        if let keys = manifest.keysInEditor, keys.isEmpty == false {
            resume.importedEditorKeys = keys
        }
        for key in sectionKeys {
            guard let behavior = manifest.behavior(forSection: key) else { continue }
            let sectionValue = value(for: key)
            switch behavior {
            case .fontSizes:
                assignFontSizes(from: sectionValue)
            case .includeFonts:
                assignIncludeFonts(from: sectionValue)
            case .editorKeys:
                assignEditorKeys(from: sectionValue)
            case .styling:
                if let dict = sectionValue as? [String: Any] {
                    assignFontSizes(from: dict["fontSizes"])
                    assignIncludeFonts(from: dict["includeFonts"])
                } else if let ordered = sectionValue as? OrderedDictionary<String, Any> {
                    assignFontSizes(from: ordered["fontSizes"])
                    assignIncludeFonts(from: ordered["includeFonts"])
                }
            case .applicantProfile, .metadata:
                break
            }
        }
        for (sectionKey, section) in manifest.sections {
            guard let sectionValue = value(for: sectionKey) else { continue }
            for field in section.fields {
                guard let behavior = field.behavior else { continue }
                let rawValue = extractRawValue(for: field, in: sectionValue)
                handleFieldBehavior(behavior, rawValue: rawValue)
            }
        }
    }
    func extractRawValue(
        for descriptor: TemplateManifest.Section.FieldDescriptor,
        in value: Any
    ) -> Any? {
        if descriptor.key == "*" { return value }
        if let ordered = value as? OrderedDictionary<String, Any> {
            return ordered[descriptor.key]
        }
        if let dict = value as? [String: Any] {
            return dict[descriptor.key]
        }
        return nil
    }
    func handleFieldBehavior(
        _ behavior: TemplateManifest.Section.FieldDescriptor.Behavior,
        rawValue: Any?
    ) {
        switch behavior {
        case .fontSizes:
            assignFontSizes(from: rawValue)
        case .includeFonts:
            assignIncludeFonts(from: rawValue)
        case .editorKeys:
            assignEditorKeys(from: rawValue)
        case .sectionLabels:
            assignSectionLabels(from: rawValue)
        case .applicantProfile:
            break
        }
    }
}
// All rendering is manifest-driven; no heuristic fallback.
