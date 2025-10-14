//
//  JsonToTree.swift
//  Sprung
//
//  Created by Christopher Culbreath on 2/27/25.
//

import Foundation
import OrderedCollections

class JsonToTree {
    private let res: Resume
    var json: OrderedDictionary<String, Any>
    private let manifest: TemplateManifest?
    private let originalContext: [String: Any]
    private let orderedSectionKeys: [String]
    /// Supplies monotonically increasing indexes during this tree build.
    private var indexCounter: Int = 0
    /// Parsed editor key instructions derived from `keys-in-editor`.
    private var editorKeyPaths: [EditorKeyPath] = []

    private struct EditorKeyPath {
        struct Segment {
            let key: String
            let hidden: Bool
        }

        let segments: [Segment]

        init?(from raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            let parts = trimmed.split(separator: ".").map(String.init)
            var segments: [Segment] = []
            segments.reserveCapacity(parts.count)
            for part in parts {
                let cleaned = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleaned.isEmpty == false else { continue }
                var hidden = false
                var name = cleaned
                if name.hasPrefix("*") {
                    hidden = true
                    name.removeFirst()
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard name.isEmpty == false else { continue }
                segments.append(Segment(key: name, hidden: hidden))
            }
            guard segments.isEmpty == false else { return nil }
            self.segments = segments
        }
    }

    private struct EditorAttributes {
        let visible: Bool
        let transparent: Bool
    }

    private init(
        resume: Resume,
        orderedContext: OrderedDictionary<String, Any>,
        manifest: TemplateManifest?,
        originalContext: [String: Any],
        orderedKeys: [String]
    ) {
        res = resume
        json = orderedContext
        self.manifest = manifest
        self.originalContext = originalContext
        orderedSectionKeys = orderedKeys
    }


    convenience init(resume: Resume, context: [String: Any], manifest: TemplateManifest?) {
        let result = JsonToTree.makeOrderedContext(from: context, manifest: manifest)
        self.init(
            resume: resume,
            orderedContext: result.orderedContext,
            manifest: manifest,
            originalContext: context,
            orderedKeys: result.orderedKeys
        )
    }


    private struct OrderedContextResult {
        let orderedContext: OrderedDictionary<String, Any>
        let orderedKeys: [String]
    }

    private static func makeOrderedContext(
        from context: [String: Any],
        manifest: TemplateManifest?
    ) -> OrderedContextResult {
#if DEBUG
        Logger.debug("JsonToTree: makeOrderedContext input keys => \(Array(context.keys))")
#endif
        var ordered: OrderedDictionary<String, Any> = [:]
        let preferredOrder = orderedKeys(from: Array(context.keys), manifest: manifest)

        for key in preferredOrder {
            if let value = context[key] {
                ordered[key] = convertToOrderedStructure(value)
            }
        }

        let extraKeys = context.keys.filter { ordered[$0] == nil }.sorted()
        for key in extraKeys {
            ordered[key] = convertToOrderedStructure(context[key] as Any)
        }

#if DEBUG
        Logger.debug("JsonToTree: makeOrderedContext ordered keys => \(Array(ordered.keys))")
#endif
        return OrderedContextResult(orderedContext: ordered, orderedKeys: Array(ordered.keys))
    }

    private func value(for key: String) -> Any? {
        if let stored = json[key] {
            return stored
        }
        guard let original = originalContext[key] else { return nil }
        return JsonToTree.convertToOrderedStructure(original)
    }

    private static func convertToOrderedStructure(_ value: Any) -> Any {
        if let orderedDict = value as? OrderedDictionary<String, Any> {
            var result: OrderedDictionary<String, Any> = [:]
            for (key, inner) in orderedDict {
                result[key] = convertToOrderedStructure(inner)
            }
            return result
        }

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

    private static func parseEditorKeyPaths(from keys: [String]) -> [EditorKeyPath] {
        keys.compactMap { EditorKeyPath(from: $0) }
    }

    private static func normalizePath(_ path: [String]) -> [String] {
        path.filter { Int($0) == nil }
    }

    private static func editorDirective(
        for normalizedPath: [String],
        keyPaths: [EditorKeyPath]
    ) -> EditorAttributes? {
        guard keyPaths.isEmpty == false else { return nil }
        guard normalizedPath.isEmpty == false else { return nil }
        var bestMatchLength: Int = -1
        var bestAttributes: EditorAttributes?

        for keyPath in keyPaths {
            let segments = keyPath.segments
            if segments.isEmpty { continue }

            // Try exact prefix matching first
            let minCount = min(normalizedPath.count, segments.count)
            var matches = true
            for index in 0..<minCount {
                if segments[index].key != normalizedPath[index] {
                    matches = false
                    break
                }
            }

            if matches {
                if normalizedPath.count <= segments.count {
                    let segmentIndex = max(0, normalizedPath.count - 1)
                    let segment = segments[segmentIndex]
                    let attributes = EditorAttributes(
                        visible: segment.hidden == false,
                        transparent: segment.hidden
                    )
                    if normalizedPath.count > bestMatchLength {
                        bestMatchLength = normalizedPath.count
                        bestAttributes = attributes
                    }
                } else {
                    // The path descends deeper than the key path. Inherit behavior from the last component.
                    if segments.count > bestMatchLength {
                        let segment = segments.last!
                        let attributes = EditorAttributes(
                            visible: segment.hidden == false,
                            transparent: segment.hidden
                        )
                        bestMatchLength = segments.count
                        bestAttributes = attributes
                    }
                }
            }
        }

        // Fallback: if no prefix match found, try matching just the leaf name
        // This allows "summary" to match ["basics", "summary"] or ["custom", "jobTitles"] to match just "jobTitles"
        if bestAttributes == nil, let leafName = normalizedPath.last {
            for keyPath in keyPaths {
                let segments = keyPath.segments
                // Single-segment paths can match any path ending with that segment
                if segments.count == 1, segments[0].key == leafName {
                    let segment = segments[0]
                    bestAttributes = EditorAttributes(
                        visible: segment.hidden == false,
                        transparent: segment.hidden
                    )
                    break
                }
            }
        }

        return bestAttributes
    }

    private func applyManifestBehaviors() {
        if res.needToFont {
            res.fontSizeNodes = []
        }
        res.includeFonts = false
        res.importedEditorKeys = []
        guard let manifest else {
            applyLegacySemantics()
            return
        }

        applySectionBehaviors(using: manifest)
        applyFieldBehaviors(using: manifest)
        applyLegacySemantics()
    }

    private func applySectionBehaviors(using manifest: TemplateManifest) {
        for key in orderedSectionKeys {
            guard let behavior = manifest.behavior(forSection: key) else { continue }
            let sectionValue = value(for: key)
            applySectionBehavior(behavior, value: sectionValue)
        }
    }

    private func applySectionBehavior(
        _ behavior: TemplateManifest.Section.Behavior,
        value: Any?
    ) {
        switch behavior {
        case .fontSizes:
            assignFontSizes(from: value)
        case .includeFonts:
            assignIncludeFonts(from: value)
        case .editorKeys:
            assignEditorKeys(from: value)
        case .styling:
            // Extract fontSizes and includeFonts from styling section
            if let stylingDict = value as? [String: Any] {
                if let fontSizes = stylingDict["fontSizes"] {
                    assignFontSizes(from: fontSizes)
                }
                if let includeFonts = stylingDict["includeFonts"] {
                    assignIncludeFonts(from: includeFonts)
                }
            } else if let orderedDict = value as? OrderedDictionary<String, Any> {
                if let fontSizes = orderedDict["fontSizes"] {
                    assignFontSizes(from: fontSizes)
                }
                if let includeFonts = orderedDict["includeFonts"] {
                    assignIncludeFonts(from: includeFonts)
                }
            }
        case .metadata, .applicantProfile:
            break
        }
    }

    private func applyFieldBehaviors(using manifest: TemplateManifest) {
        for (sectionKey, section) in manifest.sections {
            guard let sectionValue = value(for: sectionKey) else { continue }
            for descriptor in section.fields where descriptor.behavior != nil {
                guard let behavior = descriptor.behavior else { continue }
                let rawValue = rawValue(for: descriptor, in: sectionValue)
                applyFieldBehavior(behavior, value: rawValue)
            }
        }
    }

    private func applyFieldBehavior(
        _ behavior: TemplateManifest.Section.FieldDescriptor.Behavior,
        value: Any?
    ) {
        switch behavior {
        case .fontSizes:
            assignFontSizes(from: value)
        case .includeFonts:
            assignIncludeFonts(from: value)
        case .editorKeys:
            assignEditorKeys(from: value)
        case .sectionLabels:
            assignSectionLabels(from: value)
        case .applicantProfile:
            break
        }
    }

    private func applyLegacySemantics() {
        assignFontSizes(from: value(for: "font-sizes"))
        assignIncludeFonts(from: value(for: "include-fonts"))
        assignEditorKeys(from: value(for: "keys-in-editor"))
        assignSectionLabels(from: value(for: "section-labels"))
    }

    private func rawValue(
        for descriptor: TemplateManifest.Section.FieldDescriptor,
        in sectionValue: Any
    ) -> Any? {
        if descriptor.key == "*" {
            return sectionValue
        }
        if let ordered = sectionValue as? OrderedDictionary<String, Any> {
            return ordered[descriptor.key]
        }
        if let dict = sectionValue as? [String: Any] {
            return dict[descriptor.key]
        }
        return nil
    }

    private func assignFontSizes(from value: Any?) {
        guard res.needToFont else { return }
        guard let value,
              let orderedFonts = orderedDictionary(from: value) else {
            return
        }
        Logger.debug("raw font values: \(value)")
        Logger.debug("parsed font dictionary: \(orderedFonts)")
        res.needToFont = false
        var nodes: [FontSizeNode] = []
        for (key, rawValue) in orderedFonts {
            let fontString: String
            if let stringValue = rawValue as? String {
                fontString = stringValue
            } else if let numberValue = rawValue as? NSNumber {
                fontString = numberValue.stringValue + "pt"
            } else {
                fontString = String(describing: rawValue)
            }
            let idx = indexCounter
            indexCounter += 1
            let node = FontSizeNode(key: key, index: idx, fontString: fontString, resume: res)
            nodes.append(node)
        }
        res.fontSizeNodes = nodes
    }

    private func assignIncludeFonts(from value: Any?) {
        guard let value else { return }
        if let boolValue = value as? Bool {
            res.includeFonts = boolValue
        } else if let stringValue = value as? String {
            res.includeFonts = stringValue.lowercased() == "true"
        } else if let numberValue = value as? NSNumber {
            res.includeFonts = numberValue.boolValue
        }
    }

    private func assignEditorKeys(from value: Any?) {
        guard let value else { return }
        if let strings = value as? [String] {
            res.importedEditorKeys = strings
        } else if let array = value as? [Any] {
            res.importedEditorKeys = array.compactMap { $0 as? String }
        } else if let single = value as? String {
            res.importedEditorKeys = [single]
        }
    }

    private func assignSectionLabels(from value: Any?) {
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
        res.keyLabels.merge(labels) { _, new in new }
    }

    private func orderedDictionary(from value: Any) -> OrderedDictionary<String, Any>? {
        if let ordered = value as? OrderedDictionary<String, Any> {
            return ordered
        }
        if let dict = value as? [String: Any] {
            return OrderedDictionary(uniqueKeysWithValues: dict.map { ($0.key, $0.value) })
        }
        return nil
    }

    private func manifestHandlesSectionLabels() -> Bool {
        guard let manifest else { return false }
        for section in manifest.sections.values {
            if section.fields.contains(where: { $0.behavior == .sectionLabels }) {
                return true
            }
        }
        return false
    }


    func buildTree() -> TreeNode? {
        let rootNode = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: res)
        // Child indices start fresh for every new tree build.
        guard res.needToTree else {
            Logger.warning("JsonToTree.buildTree() called redundantly; returning existing root if available")
            return res.rootNode
        }
        res.needToTree = false
        applyManifestBehaviors()
        editorKeyPaths = JsonToTree.parseEditorKeyPaths(from: res.importedEditorKeys)
#if DEBUG
        Logger.debug("JsonToTree: ordered context keys => \(orderedSectionKeys)")
        for key in orderedSectionKeys {
            let typeDescription = sectionType(for: key).map(debugDescription(for:)) ?? "nil"
            Logger.debug(
                "JsonToTree: section=\(key) resolvedType=\(typeDescription) valueType=\(debugValueType(value(for: key)))"
            )
        }
#endif
        let rootAttributes = EditorAttributes(visible: true, transparent: false)
        for key in orderedSectionKeys {
            guard value(for: key) != nil else { continue }
            processSectionIfNeeded(
                named: key,
                rootNode: rootNode,
                path: [key],
                parentAttributes: rootAttributes
            )
        }
        processKeyLabels()
        promoteTransparentNodeChildren(rootNode)
        applyEditorOrdering(to: rootNode)
        return rootNode
    }

    private func processSectionIfNeeded(
        named key: String,
        rootNode: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes
    ) {
        guard shouldSkipSectionInTree(key) == false else { return }
        guard let handler = treeFunction(for: key) else { return }
        handler(key, rootNode, path, parentAttributes)
    }

    private func shouldSkipSectionInTree(_ key: String) -> Bool {
        // Skip sections that are purely metadata and shouldn't appear in the tree
        if let behavior = manifest?.behavior(forSection: key),
           [.styling, .includeFonts, .editorKeys, .metadata].contains(behavior) {
            return true
        }
        // Legacy: skip these keys if no manifest
        if manifest == nil {
            return key == "font-sizes" || key == "include-fonts" || key == "keys-in-editor"
        }
        return false
    }

    private func processKeyLabels() {
        if manifestHandlesSectionLabels() {
            return
        }
        assignSectionLabels(from: value(for: "section-labels"))
    }

    private func treeFunction(for sectionType: SectionType) -> (String, TreeNode, [String], EditorAttributes) -> Void {
        switch sectionType {
        case .object:
            return treeStringObjectSection
        case .array:
            return treeStringArraySection
        case .complex:
            return treeComplexSection
        case .string:
            return treeStringSection
        case .mapOfStrings:
            return treeMapOfStringsSection
        case .arrayOfObjects:
            return treeArrayOfObjectsSection
        case .fontSizes:
            return { _, _, _, _ in }
        }
    }

    private func treeFunction(for key: String) -> ((String, TreeNode, [String], EditorAttributes) -> Void)? {
        guard let sectionType = sectionType(for: key) else { return nil }
        return treeFunction(for: sectionType)
    }

    private func sectionType(for key: String) -> SectionType? {
        if let manifestKind = manifest?.section(for: key)?.type,
            let mapped = SectionType(manifestKind: manifestKind) {
            return mapped
        }
        return inferredSectionType(for: key)
    }

    private func orderedKeys(forKeys keys: [String]) -> [String] {
        JsonToTree.orderedKeys(from: keys, manifest: manifest)
    }

    private func editorAttributes(
        for path: [String],
        parentAttributes: EditorAttributes?
    ) -> EditorAttributes {
        let normalizedPath = JsonToTree.normalizePath(path)
        if let directive = JsonToTree.editorDirective(for: normalizedPath, keyPaths: editorKeyPaths) {
            return directive
        }
        if let parentAttributes, parentAttributes.transparent {
            return parentAttributes
        }

        // Default to hidden when editor keys are supplied; otherwise show everything.
        let shouldShowByDefault = editorKeyPaths.isEmpty
        return EditorAttributes(visible: shouldShowByDefault, transparent: false)
    }

    private func promoteTransparentNodeChildren(_ node: TreeNode) {
        guard let children = node.children else { return }
        var newChildren: [TreeNode] = []

        for child in children {
            // First, recursively process this child's subtree
            promoteTransparentNodeChildren(child)

            if child.editorTransparent {
#if DEBUG
                Logger.debug("JsonToTree.promoteTransparentNodeChildren: promoting transparent node '\(child.name)' (hasChildren: \(child.children != nil))")
#endif
                // If transparent node has children, promote those children up
                if let grandchildren = child.children {
                    for grandchild in grandchildren {
                        // Update the promoted child's name if it was empty
                        if grandchild.name.isEmpty && !child.name.isEmpty {
                            grandchild.name = "\(child.name).\(grandchild.name)".trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        }
                        newChildren.append(grandchild)
                    }
                } else {
                    // Transparent leaf node - promote the node itself but make it visible
                    child.includeInEditor = true
                    child.editorTransparent = false
                    newChildren.append(child)
#if DEBUG
                    Logger.debug("JsonToTree.promoteTransparentNodeChildren: promoted leaf node '\(child.name)'")
#endif
                }
            } else {
                // Non-transparent node - keep it
                newChildren.append(child)
            }
        }

        // Replace the node's children with the new list
        node.children = newChildren.isEmpty ? nil : newChildren

        // Second pass: remove empty container nodes that have no children and no value
        // This happens after promotion when a parent's transparent children were moved up
        if let updatedChildren = node.children {
            var finalChildren: [TreeNode] = []
            for child in updatedChildren {
                // Keep nodes that either:
                // 1. Have children, OR
                // 2. Have a non-empty value (leaf nodes with data)
                let hasChildren = child.children != nil && !child.children!.isEmpty
                let hasValue = (child.value as? String)?.isEmpty == false
                if hasChildren || hasValue {
                    finalChildren.append(child)
                } else {
#if DEBUG
                    Logger.debug("JsonToTree.promoteTransparentNodeChildren: removing empty container '\(child.name)'")
#endif
                }
            }
            node.children = finalChildren.isEmpty ? nil : finalChildren
        }
    }

    private func applyEditorOrdering(to rootNode: TreeNode) {
        guard editorKeyPaths.isEmpty == false else { return }
        guard let children = rootNode.children, children.isEmpty == false else { return }

        // Determine the desired ordering for top-level sections based on the first
        // segment encountered for each editor path.
        var topLevelOrder: [String: Int] = [:]
        for (index, keyPath) in editorKeyPaths.enumerated() {
            guard let firstSegment = keyPath.segments.first else { continue }
            let sectionName = firstSegment.key
            if topLevelOrder[sectionName] == nil {
                topLevelOrder[sectionName] = index
            }
        }
        guard topLevelOrder.isEmpty == false else { return }

        var assignedIndices = Set<Int>()
        var fallbackIndex = topLevelOrder.count

        for child in children {
            let desiredIndex = topLevelOrder[child.name]
            let newIndex: Int
            if let desiredIndex {
                newIndex = desiredIndex
            } else {
                while assignedIndices.contains(fallbackIndex) {
                    fallbackIndex += 1
                }
                newIndex = fallbackIndex
                fallbackIndex += 1
            }
            child.myIndex = newIndex
            assignedIndices.insert(newIndex)
        }
    }

    private func inferredSectionType(for key: String) -> SectionType? {
        guard let value = value(for: key) else { return nil }
        switch value {
        case is String:
            return .string
        case is [String]:
            return .array
        case let dict as [String: Any]:
            if dict.values.allSatisfy({ $0 is String }) {
                return .mapOfStrings
            }
            if dict.values.allSatisfy({ $0 is [String: Any] }) {
                return .complex
            }
            return .object
        case let ordered as OrderedDictionary<String, Any>:
            if ordered.values.allSatisfy({ $0 is String }) {
                return .mapOfStrings
            }
            if ordered.values.allSatisfy({ $0 is OrderedDictionary<String, Any> }) {
                return .complex
            }
            return .object
        case let array as [Any]:
            if array.allSatisfy({ $0 is [String: Any] || $0 is OrderedDictionary<String, Any> }) {
                return .arrayOfObjects
            }
            return .array
        default:
            return nil
        }
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

    private func treeStringArraySection(
        key: String,
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes
    ) {
        guard let flatArray = value(for: key) as? [String] else { return }
        let attributes = editorAttributes(for: path, parentAttributes: parentAttributes)
        let groupNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: attributes.visible, status: .isNotLeaf, resume: res)
        )
        groupNode.editorTransparent = attributes.transparent
        let descriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let entryDescriptor = usesDescriptor
            ? descriptor?.fields.first(where: { $0.key == "*" || $0.key == key })
            : nil
        if let entryDescriptor {
            groupNode.applyDescriptor(entryDescriptor)
        }
        treeNodesStringArray(
            strings: flatArray,
            parent: groupNode,
            path: path,
            parentAttributes: attributes,
            descriptor: entryDescriptor
        )
    }

    private func treeNodesStringArray(
        strings: [String],
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes,
        descriptor: TemplateManifest.Section.FieldDescriptor? = nil
    ) {
        let attributes = editorAttributes(for: path, parentAttributes: parentAttributes)
        if let descriptor {
            parent.applyDescriptor(descriptor)
        }
        for (index, element) in strings.enumerated() {
            let childPath = path + ["\(index)"]
            let childAttributes = editorAttributes(for: childPath, parentAttributes: attributes)
            let child = parent.addChild(
                TreeNode(name: "", value: element, inEditor: childAttributes.visible, status: .saved, resume: res)
            )
            child.editorTransparent = childAttributes.transparent
            if let descriptor {
                child.applyDescriptor(descriptor)
            }
        }
    }

    private func treeComplexSection(
        key: String,
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes
    ) {
        let attributes = editorAttributes(for: path, parentAttributes: parentAttributes)
        // Create the node for this section up front.
        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: attributes.visible, status: .isNotLeaf, resume: res)
        )
        sectionNode.editorTransparent = attributes.transparent

        let sectionDescriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let descriptorFields = usesDescriptor ? sectionDescriptor?.fields : nil

        // 1) If the value is an OrderedDictionary<String, Any> (a single dictionary).
        if let dict = asOrderedDictionary(value(for: key)) {
            if let entryDescriptor = descriptorFields?.first(where: { $0.key == "*" }) {
                for (entryKey, entryValue) in dict {
                    guard let entryDict = asOrderedDictionary(entryValue) else { continue }
                let title = displayTitle(
                    for: entryDict,
                    defaultTitle: entryKey,
                    descriptor: entryDescriptor
                )
                let childPath = path + [entryKey]
                let childAttributes = editorAttributes(for: childPath, parentAttributes: attributes)
                let itemNode = sectionNode.addChild(
                    TreeNode(name: title, value: "", inEditor: childAttributes.visible, status: .isNotLeaf, resume: res)
                )
                itemNode.editorTransparent = childAttributes.transparent
                itemNode.schemaSourceKey = entryKey
                buildSubtree(
                    from: entryDict,
                    parent: itemNode,
                    path: childPath,
                    parentAttributes: childAttributes,
                    descriptors: entryDescriptor.children
                )
            }
        } else {
            buildSubtree(
                from: dict,
                parent: sectionNode,
                path: path,
                parentAttributes: attributes,
                descriptors: descriptorFields
            )
        }
        return
    }

    if let arrayOfDicts = asOrderedArrayOfDictionaries(value(for: key)) {
        for (index, subDict) in arrayOfDicts.enumerated() {
            let defaultTitle = "\(key.capitalized) \(index + 1)"
            let itemTitle = displayTitle(
                for: subDict,
                defaultTitle: defaultTitle,
                descriptor: descriptorFields?.first(where: { $0.key == "*" })
            )
            let childPath = path + ["\(index)"]
            let childAttributes = editorAttributes(for: childPath, parentAttributes: attributes)
            let itemNode = sectionNode.addChild(
                TreeNode(name: itemTitle, value: "", inEditor: childAttributes.visible, status: .isNotLeaf, resume: res)
            )
            itemNode.editorTransparent = childAttributes.transparent
            buildSubtree(
                from: subDict,
                parent: itemNode,
                path: childPath,
                parentAttributes: childAttributes,
                descriptors: descriptorFields?.first(where: { $0.key == "*" })?.children
            )
        }
        return
    }

        // 3) Catch-all / fallback so you actually see a console message if everything else fails.
    }

    private func shouldSkipFieldInTree(_ descriptor: TemplateManifest.Section.FieldDescriptor?) -> Bool {
        guard let descriptor = descriptor, let behavior = descriptor.behavior else { return false }
        // Skip fields with behaviors that are handled as metadata or special nodes
        return [.sectionLabels, .fontSizes, .includeFonts, .editorKeys].contains(behavior)
    }

    /// Returns true if the field descriptor is a container whose children are ALL bound to ApplicantProfile
    private func isApplicantProfileContainerOnly(_ descriptor: TemplateManifest.Section.FieldDescriptor?) -> Bool {
        guard let descriptor, let children = descriptor.children, !children.isEmpty else {
            return false
        }
        // Check if ALL children have applicantProfile bindings
        return children.allSatisfy { child in
            child.binding?.source == .applicantProfile
        }
    }

    private func buildSubtree(
        from dict: OrderedDictionary<String, Any>,
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes,
        descriptors: [TemplateManifest.Section.FieldDescriptor]? = nil
    ) {
        let orderedKeys = orderedKeys(in: dict, descriptors: descriptors)
        for subKey in orderedKeys {
            guard let subValue = dict[subKey] else { continue }
            let childPath = path + [subKey]
            let childAttributes = editorAttributes(for: childPath, parentAttributes: parentAttributes)
            let childDescriptor = matchingDescriptor(
                forKey: subKey,
                in: descriptors,
                parentName: parent.name
            )

            // Skip fields bound to applicant profile - ApplicantProfile is the single source of truth
            if let descriptor = childDescriptor, descriptor.binding?.source == .applicantProfile {
                continue
            }

            // Skip container nodes that only contain ApplicantProfile-bound children (e.g., basics.location)
            if isApplicantProfileContainerOnly(childDescriptor) {
                continue
            }

            // Process fields with behaviors for metadata even if they don't appear in tree
            if let descriptor = childDescriptor, let behavior = descriptor.behavior {
                switch behavior {
                case .sectionLabels:
                    assignSectionLabels(from: subValue)
                    continue // Skip adding to tree but process the data
                case .fontSizes:
                    assignFontSizes(from: subValue)
                    continue
                case .includeFonts:
                    assignIncludeFonts(from: subValue)
                    continue
                case .editorKeys:
                    assignEditorKeys(from: subValue)
                    continue
                case .applicantProfile:
                    // These are handled separately
                    continue
                }
            }

            if let subDict = asOrderedDictionary(subValue) {
                let childDescriptors = childDescriptor?.children
                let childNode = parent.addChild(
                    TreeNode(name: subKey, value: "", inEditor: childAttributes.visible, status: .isNotLeaf, resume: res)
                )
                childNode.editorTransparent = childAttributes.transparent
                childNode.applyDescriptor(childDescriptor)
                buildSubtree(
                    from: subDict,
                    parent: childNode,
                    path: childPath,
                    parentAttributes: childAttributes,
                    descriptors: childDescriptors
                )
            } else if let subArray = subValue as? [String] {
                let arrayTitleNode = parent.addChild(
                    TreeNode(name: subKey, value: "", inEditor: childAttributes.visible, status: .isNotLeaf, resume: res)
                )
                arrayTitleNode.editorTransparent = childAttributes.transparent
                arrayTitleNode.applyDescriptor(childDescriptor)
                treeNodesStringArray(
                    strings: subArray,
                    parent: arrayTitleNode,
                    path: childPath,
                    parentAttributes: childAttributes,
                    descriptor: childDescriptor
                )
            } else if let nestedArray = subValue as? [Any] {
                let arrayTitleNode = parent.addChild(
                    TreeNode(name: subKey, value: "", inEditor: childAttributes.visible, status: .isNotLeaf, resume: res)
                )
                arrayTitleNode.editorTransparent = childAttributes.transparent
                arrayTitleNode.applyDescriptor(childDescriptor)
                for (index, element) in nestedArray.enumerated() {
                    if let stringElement = element as? String {
                        let elementPath = childPath + ["\(index)"]
                        let elementAttributes = editorAttributes(for: elementPath, parentAttributes: childAttributes)
                        let leaf = arrayTitleNode.addChild(
                            TreeNode(name: "", value: stringElement, inEditor: elementAttributes.visible, status: .saved, resume: res)
                        )
                        leaf.editorTransparent = elementAttributes.transparent
                        leaf.applyDescriptor(childDescriptor)
                    } else if let nestedDict = asOrderedDictionary(element) {
                        let elementPath = childPath + ["\(index)"]
                        let elementAttributes = editorAttributes(for: elementPath, parentAttributes: childAttributes)
                        let childNode = arrayTitleNode.addChild(
                            TreeNode(name: "", value: "", inEditor: elementAttributes.visible, status: .isNotLeaf, resume: res)
                        )
                        childNode.editorTransparent = elementAttributes.transparent
                        childNode.applyDescriptor(childDescriptor)
                        buildSubtree(
                            from: nestedDict,
                            parent: childNode,
                            path: elementPath,
                            parentAttributes: elementAttributes,
                            descriptors: childDescriptor?.children
                        )
                    }
                }
            } else if let subString = subValue as? String {
                let leaf = parent.addChild(
                    TreeNode(
                        name: subKey,
                        value: subString,
                        inEditor: childAttributes.visible,
                        status: .saved,
                        resume: res
                    )
                )
                leaf.editorTransparent = childAttributes.transparent
                leaf.applyDescriptor(childDescriptor)
            } else {}
        }
    }

    private func treeArrayOfObjectsSection(
        key: String,
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes
    ) {
        let attributes = editorAttributes(for: path, parentAttributes: parentAttributes)
        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: attributes.visible, status: .isNotLeaf, resume: res)
        )
        sectionNode.editorTransparent = attributes.transparent

        let descriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let entryDescriptor = usesDescriptor ? descriptor?.fields.first(where: { $0.key == "*" }) : nil
        if let entryDescriptor {
            sectionNode.schemaAllowsChildMutation = entryDescriptor.allowsManualMutations
            sectionNode.schemaAllowsNodeDeletion = entryDescriptor.allowsManualMutations
        }
        guard let normalizedEntries = normalizedArrayEntries(
            forKey: key,
            value: value(for: key),
            entryDescriptor: entryDescriptor
        ) else {
            return
        }

        for (index, entry) in normalizedEntries.enumerated() {
            let element = entry.value
            let defaultTitle = "\(key.capitalized) \(index + 1)"
            let title = displayTitle(
                for: element,
                defaultTitle: defaultTitle,
                descriptor: entryDescriptor
            )
            let childPath = path + ["\(index)"]
            let childAttributes = editorAttributes(for: childPath, parentAttributes: attributes)
            let entryNode = sectionNode.addChild(
                TreeNode(name: title, value: "", inEditor: childAttributes.visible, status: .isNotLeaf, resume: res)
            )
            entryNode.editorTransparent = childAttributes.transparent
            if let sourceKey = entry.sourceKey {
                entryNode.schemaSourceKey = sourceKey
            }
            if let entryDescriptor {
                entryNode.applyDescriptor(entryDescriptor)
            }
            buildSubtree(
                from: element,
                parent: entryNode,
                path: childPath,
                parentAttributes: childAttributes,
                descriptors: entryDescriptor?.children
            )
        }
    }

    private func displayTitle(
        for element: OrderedDictionary<String, Any>,
        defaultTitle: String,
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) -> String {
        if let descriptor,
           let template = descriptor.titleTemplate,
           let rendered = renderTitleTemplate(template, element: element) {
            return rendered
        }

        let titleKeys = ["title", "name", "position", "employer"]
        for key in titleKeys {
            if let value = element[key] as? String, !value.isEmpty {
                return value
            }
        }
        for value in element.values {
            if let string = value as? String, !string.isEmpty {
                return string
            }
        }
        return defaultTitle
    }

    private func treeStringSection(
        key: String,
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes
    ) {
        guard let sectionString = value(for: key) as? String else { return }
        let attributes = editorAttributes(for: path, parentAttributes: parentAttributes)
        let descriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let fieldDescriptor = usesDescriptor
            ? descriptor?.fields.first(where: { $0.key == key || $0.key == "*" })
            : nil

        // Create a single collapsible node with name and value
        // This renders as "summary >" that expands to show the full text
        let leafNode = parent.addChild(
            TreeNode(name: key, value: sectionString, inEditor: attributes.visible, status: .saved, resume: res)
        )
        leafNode.editorTransparent = attributes.transparent
        if let fieldDescriptor {
            leafNode.applyDescriptor(fieldDescriptor)
        }
    }

    private func treeStringObjectSection(
        key: String,
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes
    ) {
        guard let sectionDict = asOrderedDictionary(value(for: key)) else { return }
        let attributes = editorAttributes(for: path, parentAttributes: parentAttributes)

        let descriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let descriptorFields = usesDescriptor ? descriptor?.fields : nil
        let ordered = orderedKeys(in: sectionDict, descriptors: descriptorFields)

        // Count how many children would actually be visible after filtering
        var visibleChildCount = 0
        for entryKey in ordered {
            guard sectionDict[entryKey] != nil else { continue }
            let childPath = path + [entryKey]
            let childDescriptor = matchingDescriptor(forKey: entryKey, in: descriptorFields, parentName: key)

            // Skip if bound to applicant profile
            if let desc = childDescriptor, desc.binding?.source == .applicantProfile {
                continue
            }
            // Skip if container only has applicant profile children
            if isApplicantProfileContainerOnly(childDescriptor) {
                continue
            }
            // Skip if it has a behavior that filters it
            if let desc = childDescriptor, let behavior = desc.behavior,
               [.sectionLabels, .fontSizes, .includeFonts, .editorKeys, .applicantProfile].contains(behavior) {
                continue
            }
            visibleChildCount += 1
        }

        // If all children would be filtered, don't create the parent container
        if visibleChildCount == 0 {
            return
        }

        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: attributes.visible, status: .isNotLeaf, resume: res)
        )
        sectionNode.editorTransparent = attributes.transparent

        // Build the tree naturally - let promoteTransparentNodeChildren() handle promotion later
        for entryKey in ordered {
            guard let entryValue = sectionDict[entryKey] else { continue }
            let childPath = path + [entryKey]
            let childAttributes = editorAttributes(for: childPath, parentAttributes: attributes)
            let childDescriptor = matchingDescriptor(
                forKey: entryKey,
                in: descriptorFields,
                parentName: key
            )

            // Skip fields bound to applicant profile - ApplicantProfile is the single source of truth
            if let descriptor = childDescriptor, descriptor.binding?.source == .applicantProfile {
                continue
            }

            // Skip container nodes that only contain ApplicantProfile-bound children (e.g., basics.location)
            if isApplicantProfileContainerOnly(childDescriptor) {
                continue
            }

            // Process fields with behaviors for metadata even if they don't appear in tree
            if let descriptor = childDescriptor, let behavior = descriptor.behavior {
                switch behavior {
                case .sectionLabels:
                    assignSectionLabels(from: entryValue)
                    continue
                case .fontSizes:
                    assignFontSizes(from: entryValue)
                    continue
                case .includeFonts:
                    assignIncludeFonts(from: entryValue)
                    continue
                case .editorKeys:
                    assignEditorKeys(from: entryValue)
                    continue
                case .applicantProfile:
                    continue
                }
            }

            if let stringValue = entryValue as? String {
                let child = sectionNode.addChild(
                    TreeNode(
                        name: entryKey,
                        value: stringValue,
                        inEditor: childAttributes.visible,
                        status: .saved,
                        resume: res
                    )
                )
                child.editorTransparent = childAttributes.transparent
                child.applyDescriptor(childDescriptor)
            } else if let dictValue = asOrderedDictionary(entryValue) {
                let childNode = sectionNode.addChild(
                    TreeNode(
                        name: entryKey,
                        value: "",
                        inEditor: childAttributes.visible,
                        status: .isNotLeaf,
                        resume: res
                    )
                )
                childNode.editorTransparent = childAttributes.transparent
                childNode.applyDescriptor(childDescriptor)
                let childDescriptors = childDescriptor?.children
                buildSubtree(
                    from: dictValue,
                    parent: childNode,
                    path: childPath,
                    parentAttributes: childAttributes,
                    descriptors: childDescriptors
                )
            } else if let stringArray = entryValue as? [String] {
                let childNode = sectionNode.addChild(
                    TreeNode(
                        name: entryKey,
                        value: "",
                        inEditor: childAttributes.visible,
                        status: .isNotLeaf,
                        resume: res
                    )
                )
                childNode.editorTransparent = childAttributes.transparent
                treeNodesStringArray(
                    strings: stringArray,
                    parent: childNode,
                    path: childPath,
                    parentAttributes: childAttributes,
                    descriptor: childDescriptor
                )
            }
        }
    }

    private func treeMapOfStringsSection(
        key: String,
        parent: TreeNode,
        path: [String],
        parentAttributes: EditorAttributes
    ) {
        guard let sectionDict = asOrderedDictionary(value(for: key)) else { return }
        let attributes = editorAttributes(for: path, parentAttributes: parentAttributes)
        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: attributes.visible, status: .isNotLeaf, resume: res)
        )
        sectionNode.editorTransparent = attributes.transparent
        let sectionDescriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let descriptorFields = usesDescriptor ? sectionDescriptor?.fields : nil
        let ordered = orderedKeys(in: sectionDict, descriptors: descriptorFields)

        for entryKey in ordered {
            guard let entryValue = sectionDict[entryKey] else { continue }
            guard let label = entryValue as? String else { continue }
            let childPath = path + [entryKey]
            let childAttributes = editorAttributes(for: childPath, parentAttributes: attributes)
            res.keyLabels[entryKey] = label
            let child = sectionNode.addChild(
                TreeNode(
                    name: entryKey,
                    value: label,
                    inEditor: childAttributes.visible,
                    status: .saved,
                    resume: res
                )
            )
            child.editorTransparent = childAttributes.transparent
            let childDescriptor = matchingDescriptor(
                forKey: entryKey,
                in: descriptorFields,
                parentName: key
            )
            child.applyDescriptor(childDescriptor)
        }
    }

    private func orderedKeys(
        in dict: OrderedDictionary<String, Any>,
        descriptors: [TemplateManifest.Section.FieldDescriptor]?
    ) -> [String] {
        guard let descriptors, !descriptors.isEmpty else {
            return Array(dict.keys)
        }
        var ordered: [String] = []
        for descriptor in descriptors where descriptor.key != "*" {
            if dict.keys.contains(descriptor.key) {
                ordered.append(descriptor.key)
            }
        }
        for key in dict.keys where !ordered.contains(key) {
            ordered.append(key)
        }
        return ordered
    }

    private func matchingDescriptor(
        forKey key: String,
        in descriptors: [TemplateManifest.Section.FieldDescriptor]?,
        parentName: String?
    ) -> TemplateManifest.Section.FieldDescriptor? {
        guard let descriptors else { return nil }
        if let exact = descriptors.first(where: { $0.key == key }) {
            return exact
        }
        if let parentName,
           let parentMatch = descriptors.first(where: { $0.key == parentName }) {
            return parentMatch
        }
        if key.isEmpty, let wildcard = descriptors.first(where: { $0.key == "*" }) {
            return wildcard
        }
        return descriptors.first(where: { $0.key == "*" })
    }

    private func renderTitleTemplate(
        _ template: String,
        element: OrderedDictionary<String, Any>
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
            guard let replacement = element[key] as? String, replacement.isEmpty == false else {
                return nil
            }
            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }

    private func asOrderedDictionary(_ value: Any?) -> OrderedDictionary<String, Any>? {
        if let ordered = value as? OrderedDictionary<String, Any> {
            return ordered
        }
        if let dict = value as? [String: Any] {
            var ordered: OrderedDictionary<String, Any> = [:]
            for (key, inner) in dict {
                ordered[key] = JsonToTree.convertToOrderedStructure(inner)
            }
            return ordered
        }
        return nil
    }

    private func asOrderedArrayOfDictionaries(_ value: Any?) -> [OrderedDictionary<String, Any>]? {
        if let ordered = value as? [OrderedDictionary<String, Any>] {
            return ordered
        }
        if let array = value as? [[String: Any]] {
            return array.map { dict in
                var ordered: OrderedDictionary<String, Any> = [:]
                for (key, inner) in dict {
                    ordered[key] = JsonToTree.convertToOrderedStructure(inner)
                }
                return ordered
            }
        }
        if let array = value as? [Any] {
            return array.compactMap { element -> OrderedDictionary<String, Any>? in
                if let dict = element as? [String: Any] {
                    return asOrderedDictionary(dict)
                }
                return element as? OrderedDictionary<String, Any>
            }
        }
        return nil
    }

    private func asOrderedDictionary(_ dict: [String: Any]) -> OrderedDictionary<String, Any> {
        var ordered: OrderedDictionary<String, Any> = [:]
        for (key, value) in dict {
            ordered[key] = JsonToTree.convertToOrderedStructure(value)
        }
        return ordered
    }

    private struct ArrayEntry {
        let sourceKey: String?
        let value: OrderedDictionary<String, Any>
    }

    private func normalizedArrayEntries(
        forKey key: String,
        value: Any?,
        entryDescriptor: TemplateManifest.Section.FieldDescriptor?
    ) -> [ArrayEntry]? {
        if let array = asOrderedArrayOfDictionaries(value) {
            return array.map { dictionary in
                var entry = dictionary
                let sourceKey = (entry["__key"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if sourceKey != nil {
                    entry.removeValue(forKey: "__key")
                }
                return ArrayEntry(sourceKey: sourceKey, value: entry)
            }
        }

        if let orderedDict = asOrderedDictionary(value) {
            var entries: [ArrayEntry] = []
            for (entryKey, entryValue) in orderedDict {
                if let nested = asOrderedDictionary(entryValue) {
                    var normalized = nested
                    ensureTitle(in: &normalized, fallbackKey: entryKey, descriptor: entryDescriptor)
                    entries.append(ArrayEntry(sourceKey: entryKey, value: normalized))
                    continue
                }

                if let stringValue = entryValue as? String {
                    var normalized = OrderedDictionary<String, Any>()
                    assignTitleAndPrimaryValue(
                        to: &normalized,
                        title: entryKey,
                        value: stringValue,
                        descriptor: entryDescriptor
                    )
                    entries.append(ArrayEntry(sourceKey: entryKey, value: normalized))
                    continue
                }

                if let arrayValue = entryValue as? [Any] {
                    var normalized = OrderedDictionary<String, Any>()
                    normalized["title"] = entryKey
                    normalized["items"] = JsonToTree.convertToOrderedStructure(arrayValue)
                    entries.append(ArrayEntry(sourceKey: entryKey, value: normalized))
                    continue
                }
            }
            return entries.isEmpty ? nil : entries
        }

        if let arrayOfStrings = value as? [String] {
            return arrayOfStrings.map { stringValue in
                var normalized = OrderedDictionary<String, Any>()
                normalized["title"] = stringValue
                return ArrayEntry(sourceKey: nil, value: normalized)
            }
        }

        return nil
    }

    private func ensureTitle(
        in entry: inout OrderedDictionary<String, Any>,
        fallbackKey: String,
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) {
        if let descriptor,
           let titleField = descriptor.children?.first(where: { $0.key == "title" }),
           entry[titleField.key] == nil {
            entry[titleField.key] = fallbackKey
            return
        }
        if entry["title"] == nil {
            entry["title"] = fallbackKey
        }
    }

    private func assignTitleAndPrimaryValue(
        to entry: inout OrderedDictionary<String, Any>,
        title: String,
        value: String,
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) {
        if let descriptor, let children = descriptor.children, !children.isEmpty {
            let titleDescriptor = children.first(where: { $0.key == "title" }) ?? children.first
            if let titleDescriptor {
                entry[titleDescriptor.key] = title
            } else {
                entry["title"] = title
            }
            if let descriptionDescriptor = children.first(where: { $0.key != titleDescriptor?.key }) {
                entry[descriptionDescriptor.key] = value
            } else {
                entry["value"] = value
            }
        } else {
            entry["title"] = title
            entry["value"] = value
        }
    }

}

#if DEBUG
extension JsonToTree {
    private func debugDescription(for sectionType: SectionType) -> String {
        switch sectionType {
        case .object:
            return "object"
        case .array:
            return "array"
        case .complex:
            return "complex"
        case .string:
            return "string"
        case .mapOfStrings:
            return "mapOfStrings"
        case .arrayOfObjects:
            return "arrayOfObjects"
        case .fontSizes:
            return "fontSizes"
        }
    }

    private func debugValueType(_ value: Any?) -> String {
        guard let value else { return "nil" }
        switch value {
        case is OrderedDictionary<String, Any>:
            return "OrderedDictionary"
        case is [String: Any]:
            return "Dictionary"
        case is [Any]:
            return "Array"
        case is String:
            return "String"
        default:
            return String(describing: type(of: value))
        }
    }
}
#endif
