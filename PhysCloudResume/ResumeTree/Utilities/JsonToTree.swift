//
//  JsonToTree.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import Foundation
import OrderedCollections

class JsonToTree {
    private let res: Resume
    var json: OrderedDictionary<String, Any>
    private let manifest: TemplateManifest?
    private static let specialKeys: Set<String> = ["font-sizes", "include-fonts"]
    private static let fallbackSectionOrder: [String] = [
        "meta",
        "font-sizes",
        "include-fonts",
        "section-labels",
        "contact",
        "summary",
        "job-titles",
        "employment",
        "education",
        "skills-and-expertise",
        "languages",
        "projects-highlights",
        "projects-and-hobbies",
        "publications",
        "keys-in-editor",
        "more-info"
    ]
    /// Supplies monotonically increasing indexes during this tree build.
    private var indexCounter: Int = 0

    private init(resume: Resume, orderedContext: OrderedDictionary<String, Any>, manifest: TemplateManifest?) {
        res = resume
        json = orderedContext
        self.manifest = manifest
    }

    convenience init?(resume: Resume, rawJson: String, manifest: TemplateManifest? = nil) {
        guard let orderedDictJson = JsonToTree.parseUnwrapJson(rawJson, manifest: manifest) else {
            return nil
        }
        self.init(resume: resume, orderedContext: orderedDictJson, manifest: manifest)
    }

    convenience init(resume: Resume, context: [String: Any], manifest: TemplateManifest?) {
        self.init(
            resume: resume,
            orderedContext: JsonToTree.makeOrderedContext(from: context, manifest: manifest),
            manifest: manifest
        )
    }

    private func isInEditor(_ key: String) -> Bool {
        return res.importedEditorKeys.contains(key)
    }

    private static func parseUnwrapJson(_ rawJson: String, manifest: TemplateManifest?) -> OrderedDictionary<String, Any>? {
        guard let data = rawJson.data(using: .utf8) else { return nil }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = obj as? [String: Any] else { return nil }

            return makeOrderedContext(from: dict, manifest: manifest)
        } catch {
            Logger.error("JsonToTree: Failed to parse model JSON: \(error)")
            return nil
        }
    }

    private static func makeOrderedContext(
        from context: [String: Any],
        manifest: TemplateManifest?
    ) -> OrderedDictionary<String, Any> {
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

        return ordered
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

    func buildTree() -> TreeNode? {
        let rootNode = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: res)
        // Child indices start fresh for every new tree build.
        guard res.needToTree else {
            Logger.warning("JsonToTree.buildTree() called redundantly; returning existing root if available")
            return res.rootNode
        }
        res.needToTree = false
        parseSpecialKeys()
        var processed: Set<String> = []
        for key in orderedKeys(forKeys: Array(json.keys)) {
            guard json[key] != nil else { continue }
            processSectionIfNeeded(named: key, rootNode: rootNode)
            processed.insert(key)
        }

        // Include any remaining keys that were not part of the manifest order
        for key in json.keys where !processed.contains(key) {
            processSectionIfNeeded(named: key, rootNode: rootNode)
        }
        processKeyLabels()
        return rootNode
    }

    private func processSectionIfNeeded(named key: String, rootNode: TreeNode) {
        guard JsonToTree.specialKeys.contains(key) == false else { return }
        guard let handler = treeFunction(for: key) else { return }
        handler(key, rootNode)
    }

    private func parseInclude(key: String) -> Bool {
        if let myString = json[key] as? String {
            if myString == "true" {
                return true
            }
        }
        return false
    }

    private func parseSpecialKeys() {
        res.fontSizeNodes = parseFontSizeSection(key: "font-sizes")
        res.includeFonts = parseInclude(key: "include-fonts")
        res.importedEditorKeys = parseStringArray(key: "keys-in-editor")
    }

    private func processKeyLabels() {
        if let labelDict = json["section-labels"] as? OrderedDictionary<String, Any> {
            for key in labelDict.keys {
                if let value = labelDict[key] { // Correct dictionary access
                    res.keyLabels[key] = value as? String ?? "Error!" // Assigning the value correctly
                }
            }
        } else {}
    }

    private func parseFontSizeSection(key: String) -> [FontSizeNode] {
        guard res.needToFont else {
            Logger.warning("JsonToTree.parseFontSizeSection() called redundantly; returning existing font sizes")
            return res.fontSizeNodes
        }
        res.needToFont = false
        let orderedFonts: OrderedDictionary<String, Any>
        if let fontArray = json[key] as? OrderedDictionary<String, Any> {
            orderedFonts = fontArray
        } else if let dict = json[key] as? [String: Any] {
            orderedFonts = OrderedDictionary(uniqueKeysWithValues: dict.map { ($0.key, $0.value) })
        } else {
            return []
        }

        var nodes: [FontSizeNode] = []
        for (myKey, myValue) in orderedFonts {
            let fontString = myValue as? String ?? ""
            let idx = indexCounter
            indexCounter += 1
            let node = FontSizeNode(key: myKey, index: idx, fontString: fontString, resume: res)
            nodes.append(node)
        }

        return nodes
    }

    func treeFunction(for sectionType: SectionType) -> (String, TreeNode) -> Void {
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
            return { _, _ in }
        }
    }

    private func treeFunction(for key: String) -> ((String, TreeNode) -> Void)? {
        guard let sectionType = sectionType(for: key) else { return nil }
        return treeFunction(for: sectionType)
    }

    private func sectionType(for key: String) -> SectionType? {
        if let manifestKind = manifest?.section(for: key)?.type,
           let mapped = SectionType(manifestKind: manifestKind, key: key) {
            return mapped
        }
        return inferredSectionType(for: key)
    }

    private func orderedKeys(forKeys keys: [String]) -> [String] {
        JsonToTree.orderedKeys(from: keys, manifest: manifest)
    }

    private func inferredSectionType(for key: String) -> SectionType? {
        guard let value = json[key] else { return nil }
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
        var ordered: [String] = []
        if let manifestOrder = manifest?.sectionOrder {
            for key in manifestOrder where keys.contains(key) {
                ordered.append(key)
            }
        } else {
            for key in fallbackSectionOrder where keys.contains(key) {
                ordered.append(key)
            }
        }
        let extras = keys.filter { !ordered.contains($0) }.sorted()
        ordered.append(contentsOf: extras)
        return ordered
    }

    private func parseStringArray(key: String) -> [String] {
        if let stringArray = json[key] as? [String] {
            return stringArray
        } else { return [] }
    }

    private func treeStringArraySection(key: String, parent: TreeNode) {
        let inEditor = isInEditor(key)
        if let flatArray = json[key] as? [String] {
            let groupNode = parent.addChild(TreeNode(name: key, value: "", inEditor: isInEditor(key), status: .isNotLeaf, resume: res))
            treeNodesStringArray(strings: flatArray, parent: groupNode, inEditor: inEditor)
        }
    }

    private func treeNodesStringArray(strings: [String], parent: TreeNode, inEditor: Bool) {
        for element in strings {
            parent.addChild(TreeNode(name: "", value: element, inEditor: inEditor, status: .saved, resume: res))
        }
    }

    private func treeComplexSection(key: String, parent: TreeNode) {
        let inEditor = isInEditor(key)

        // Create the node for this section up front.
        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
        )

        let sectionDescriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let descriptorFields = usesDescriptor ? sectionDescriptor?.fields : nil

        // 1) If the value is an OrderedDictionary<String, Any> (a single dictionary).
        if let dict = asOrderedDictionary(json[key]) {
            if let entryDescriptor = descriptorFields?.first(where: { $0.key == "*" }) {
                for (entryKey, entryValue) in dict {
                    guard let entryDict = asOrderedDictionary(entryValue) else { continue }
                    let title = displayTitle(
                        for: entryDict,
                        defaultTitle: entryKey,
                        descriptor: entryDescriptor
                    )
                    let itemNode = sectionNode.addChild(
                        TreeNode(name: title, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
                    )
                    buildSubtree(
                        from: entryDict,
                        parent: itemNode,
                        inEditor: inEditor,
                        descriptors: entryDescriptor.children
                    )
                }
            } else {
                buildSubtree(
                    from: dict,
                    parent: sectionNode,
                    inEditor: inEditor,
                    descriptors: descriptorFields
                )
            }
            return
        }

        if let arrayOfDicts = asOrderedArrayOfDictionaries(json[key]) {
            for (index, subDict) in arrayOfDicts.enumerated() {
                let defaultTitle = "\(key.capitalized) \(index + 1)"
                let itemTitle = displayTitle(
                    for: subDict,
                    defaultTitle: defaultTitle,
                    descriptor: descriptorFields?.first(where: { $0.key == "*" })
                )
                let itemNode = sectionNode.addChild(
                    TreeNode(name: itemTitle, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
                )
                buildSubtree(
                    from: subDict,
                    parent: itemNode,
                    inEditor: inEditor,
                    descriptors: descriptorFields?.first(where: { $0.key == "*" })?.children
                )
            }
            return
        }

        // 3) Catch-all / fallback so you actually see a console message if everything else fails.
    }

    private func buildSubtree(
        from dict: OrderedDictionary<String, Any>,
        parent: TreeNode,
        inEditor: Bool,
        descriptors: [TemplateManifest.Section.FieldDescriptor]? = nil
    ) {
        let orderedKeys = orderedKeys(in: dict, descriptors: descriptors)
        for subKey in orderedKeys {
            guard let subValue = dict[subKey] else { continue }
            if let subDict = asOrderedDictionary(subValue) {
                let childDescriptors = descriptors?.first(where: { $0.key == subKey })?.children
                let childNode = parent.addChild(
                    TreeNode(name: subKey, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
                )
                buildSubtree(
                    from: subDict,
                    parent: childNode,
                    inEditor: inEditor,
                    descriptors: childDescriptors
                )
            } else if let subArray = subValue as? [String] {
                let arrayTitleNode = parent.addChild(TreeNode(name: subKey, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res))
                treeNodesStringArray(strings: subArray, parent: arrayTitleNode, inEditor: inEditor)
            } else if let nestedArray = subValue as? [Any] {
                let arrayTitleNode = parent.addChild(
                    TreeNode(name: subKey, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
                )
                let childDescriptor = descriptors?.first(where: { $0.key == subKey })
                for element in nestedArray {
                    if let stringElement = element as? String {
                        arrayTitleNode.addChild(
                            TreeNode(name: "", value: stringElement, inEditor: inEditor, status: .saved, resume: res)
                        )
                    } else if let nestedDict = asOrderedDictionary(element) {
                        let childNode = arrayTitleNode.addChild(
                            TreeNode(name: "", value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
                        )
                        buildSubtree(
                            from: nestedDict,
                            parent: childNode,
                            inEditor: inEditor,
                            descriptors: childDescriptor?.children
                        )
                    }
                }
            } else if let subString = subValue as? String {
                parent.addChild(
                    TreeNode(
                        name: subKey,
                        value: subString,
                        inEditor: inEditor, status: .saved,
                        resume: res
                    )
                )
            } else {}
        }
    }

    private func treeArrayOfObjectsSection(key: String, parent: TreeNode) {
        guard let sectionArray = asOrderedArrayOfDictionaries(json[key]) else { return }
        let inEditor = isInEditor(key)
        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
        )

        let descriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let entryDescriptor = usesDescriptor ? descriptor?.fields.first(where: { $0.key == "*" }) : nil

        for (index, element) in sectionArray.enumerated() {
            let defaultTitle = "\(key.capitalized) \(index + 1)"
            let title = displayTitle(
                for: element,
                defaultTitle: defaultTitle,
                descriptor: entryDescriptor
            )
            let entryNode = sectionNode.addChild(
                TreeNode(name: title, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
            )
            buildSubtree(
                from: element,
                parent: entryNode,
                inEditor: inEditor,
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

    private func treeStringSection(key: String, parent: TreeNode) {
        if let sectionString = json[key] as? String {
            let sectionNode = parent.addChild(
                TreeNode(name: key, value: "", inEditor: isInEditor(key), status: .isNotLeaf, resume: res))
            sectionNode.addChild(TreeNode(name: "", value: sectionString, inEditor: isInEditor(key), status: .saved, resume: res))
        }
    }

    private func treeStringObjectSection(key: String, parent: TreeNode) {
        if let sectionDict = asOrderedDictionary(json[key]) {
            let sectionNode = parent.addChild(
                TreeNode(name: key, value: "", inEditor: isInEditor(key), status: .isNotLeaf, resume: res))
            let descriptor = manifest?.section(for: key)
            let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
            let ordered = orderedKeys(in: sectionDict, descriptors: usesDescriptor ? descriptor?.fields : nil)

            for entryKey in ordered {
                guard let entryValue = sectionDict[entryKey] else { continue }
                if let stringValue = entryValue as? String {
                    sectionNode.addChild(
                        TreeNode(
                            name: entryKey,
                            value: stringValue,
                            inEditor: isInEditor(key),
                            status: .saved,
                            resume: res
                        )
                    )
                } else if let dictValue = asOrderedDictionary(entryValue) {
                    let childNode = sectionNode.addChild(
                        TreeNode(
                            name: entryKey,
                            value: "",
                            inEditor: isInEditor(key),
                            status: .isNotLeaf,
                            resume: res
                        )
                    )
                    let childDescriptors = descriptor?.fields.first(where: { $0.key == entryKey })?.children
                    buildSubtree(
                        from: dictValue,
                        parent: childNode,
                        inEditor: isInEditor(key),
                        descriptors: childDescriptors
                    )
                } else if let stringArray = entryValue as? [String] {
                    let childNode = sectionNode.addChild(
                        TreeNode(
                            name: entryKey,
                            value: "",
                            inEditor: isInEditor(key),
                            status: .isNotLeaf,
                            resume: res
                        )
                    )
                    treeNodesStringArray(strings: stringArray, parent: childNode, inEditor: isInEditor(key))
                }
            }
        } else {}
    }

    private func treeMapOfStringsSection(key: String, parent: TreeNode) {
        guard let sectionDict = asOrderedDictionary(json[key]) else { return }
        let inEditor = isInEditor(key)
        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
        )
        let descriptor = manifest?.section(for: key)
        let usesDescriptor = !(manifest?.isFieldMetadataSynthesized(for: key) ?? true)
        let ordered = orderedKeys(in: sectionDict, descriptors: usesDescriptor ? descriptor?.fields : nil)

        for entryKey in ordered {
            guard let entryValue = sectionDict[entryKey] else { continue }
            guard let label = entryValue as? String else { continue }
            res.keyLabels[entryKey] = label
            sectionNode.addChild(
                TreeNode(
                    name: entryKey,
                    value: label,
                    inEditor: inEditor,
                    status: .saved,
                    resume: res
                )
            )
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
}
