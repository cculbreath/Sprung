import Foundation

struct DescriptorInterpreter {
    let resume: Resume
    let manifest: TemplateManifest?
    let fontScaler: FontSizeScaler
    let valueNormalizer: SectionValueNormalizer
    let titleRenderer: TitleTemplateRenderer
    let validator: DescriptorValueValidator
    let sectionNodeProvider: (String) -> TreeNode?
    let nodeValueProvider: (TreeNode) -> Any?
    let fontSizesFallback: () -> [String: String]?
    let rawSectionBuilder: (String, SectionType) -> Any?

    func buildSection(named sectionName: String, section: TemplateManifest.Section) -> Any? {
        let sectionNode = sectionNodeProvider(sectionName)
        let descriptors = section.fields

        switch section.type {
        case .string:
            guard let descriptor = descriptors.first else {
                return rawBuild(sectionName, kind: section.type)
            }
            let valueNode = node(for: descriptor, in: sectionNode)
            return buildValue(for: descriptor, node: valueNode)

        case .array, .arrayOfObjects:
            guard let descriptor = descriptors.first else {
                return rawBuild(sectionName, kind: section.type)
            }
            let arrayNode = node(for: descriptor, in: sectionNode)
            return buildValue(for: descriptor, node: arrayNode)

        case .mapOfStrings:
            guard let sectionNode else { return nil }
            var result: [String: String] = [:]
            for descriptor in descriptors where descriptor.key != "*" {
                let childNode = node(for: descriptor, in: sectionNode)
                if let value = buildValue(for: descriptor, node: childNode) as? String {
                    result[descriptor.key] = value
                }
            }
            return result.isEmpty ? nil : result

        case .fontSizes:
            guard let sectionNode else { return nil }
            var result: [String: String] = [:]
            for descriptor in descriptors where descriptor.key != "*" {
                let childNode = node(for: descriptor, in: sectionNode)
                if let value = buildValue(for: descriptor, node: childNode) as? String {
                    result[descriptor.key] = value
                }
            }
            guard result.isEmpty == false else { return nil }
            return fontScaler.scaleFontSizes(result)

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
                } else if var entryDict = nodeValueProvider(child) as? [String: Any] {
                    decorateEntry(&entryDict, descriptor: entryDescriptor, key: keyCandidate)
                    dictionary[keyCandidate] = entryDict
                } else if let value = nodeValueProvider(child) {
                    dictionary[keyCandidate] = value
                }
            }
            if dictionary.isEmpty == false {
                return dictionary
            }
            if let entryDescriptor {
                return buildValue(for: entryDescriptor, node: sectionNode)
            }
            return nil
        }
    }

    private func rawBuild(_ sectionName: String, kind: TemplateManifest.Section.Kind) -> Any? {
        guard let sectionType = SectionType(manifestKind: kind) else { return nil }
        return rawSectionBuilder(sectionName, sectionType)
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
                        } else if var dict = nodeValueProvider(child) as? [String: Any] {
                            let keyCandidate = resolvedKey(from: child, fallback: "\(index)")
                            decorateEntry(&dict, descriptor: descriptor, key: keyCandidate)
                            items.append(dict)
                        } else if let primitive = nodeValueProvider(child) {
                            var wrapper: [String: Any] = ["value": primitive]
                            let keyCandidate = resolvedKey(from: child, fallback: "\(index)")
                            decorateEntry(&wrapper, descriptor: descriptor, key: keyCandidate)
                            items.append(wrapper)
                        }
                    }
                    if items.isEmpty == false {
                        return valueNormalizer.normalize(items, for: descriptor.behavior)
                    }
                } else {
                    let values = node.orderedChildren
                        .map { $0.value }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if values.isEmpty == false {
                        return valueNormalizer.normalize(values, for: descriptor.behavior)
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
                return valueNormalizer.normalize(object, for: descriptor.behavior)
            }

            if let behavior = descriptor.behavior {
                return fallbackValue(for: behavior, node: node)
            }
            return nil
        }

        if let node {
            if node.hasChildren, let nested = nodeValueProvider(node) {
                return valueNormalizer.normalize(nested, for: descriptor.behavior)
            }

            if node.value.isEmpty == false {
                return valueNormalizer.normalize(node.value, for: descriptor.behavior)
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
            return nodeValueProvider(node) as? [String: Any]
        }

        return result
    }

    private func resolveBinding(
        _ binding: TemplateManifest.Section.FieldDescriptor.Binding?
    ) -> Any? {
        guard let binding else { return nil }
        switch binding.source {
        case .applicantProfile:
            return nil
        }
    }

    private func fallbackValue(
        for behavior: TemplateManifest.Section.FieldDescriptor.Behavior,
        node: TreeNode?
    ) -> Any? {
        if let node,
           let raw = nodeValueProvider(node) {
            let normalized = valueNormalizer.normalize(raw, for: behavior)
            if valueNormalizer.isEmpty(normalized) == false {
                return normalized
            }
        }

        switch behavior {
        case .fontSizes:
            if let fallback = fontSizesFallback() {
                return valueNormalizer.normalize(fallback, for: behavior)
            }
            return nil

        case .includeFonts:
            let includeFonts = resume.includeFonts ? "true" : "false"
            return valueNormalizer.normalize(includeFonts, for: behavior)

        case .editorKeys:
            guard resume.importedEditorKeys.isEmpty == false else { return nil }
            return valueNormalizer.normalize(resume.importedEditorKeys, for: behavior)

        case .sectionLabels:
            guard resume.keyLabels.isEmpty == false else { return nil }
            return valueNormalizer.normalize(resume.keyLabels, for: behavior)

        case .applicantProfile:
            return nil
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
            for placeholder in titleRenderer.placeholders(in: template) {
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
           let computed = titleRenderer.render(template, context: titleContext) {
            meta["title"] = computed
        }

        let validation = validator.validate(entry, descriptor: descriptor)
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
}
