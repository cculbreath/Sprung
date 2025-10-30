import Foundation

struct SectionBuilder {
    let resume: Resume
    let sectionNodeProvider: (String) -> TreeNode?
    let nodeValueProvider: (TreeNode) -> Any?

    init(
        resume: Resume,
        sectionNodeProvider: @escaping (String) -> TreeNode?,
        nodeValueProvider: @escaping (TreeNode) -> Any?
    ) {
        self.resume = resume
        self.sectionNodeProvider = sectionNodeProvider
        self.nodeValueProvider = nodeValueProvider
    }

    func buildSection(named sectionName: String, type: SectionType) -> Any? {
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
            return nil
        }
    }

    private func buildObjectSection(named sectionName: String) -> [String: Any]? {
        guard let sectionNode = sectionNodeProvider(sectionName) else { return nil }
        var result: [String: Any] = [:]

        for child in sectionNode.orderedChildren {
            guard !child.name.isEmpty else { continue }

            if let nested = nodeValueProvider(child) {
                result[child.name] = nested
            } else if !child.value.isEmpty {
                result[child.name] = child.value
            }
        }

        return result.isEmpty ? nil : result
    }

    private func buildMapOfStringsSection(named sectionName: String) -> [String: String]? {
        guard let sectionNode = sectionNodeProvider(sectionName) else { return nil }
        var result: [String: String] = [:]
        for child in sectionNode.orderedChildren {
            let label = resume.keyLabels[child.name] ?? (child.value.isEmpty ? child.name : child.value)
            result[child.name] = label
        }
        return result.isEmpty ? nil : result
    }

    private func buildArraySection(named sectionName: String) -> [Any]? {
        guard let sectionNode = sectionNodeProvider(sectionName) else { return nil }

        let values = sectionNode.orderedChildren
            .map { $0.value }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return values.isEmpty ? nil : values
    }

    private func buildStringSection(named sectionName: String) -> Any? {
        guard let sectionNode = sectionNodeProvider(sectionName) else { return nil }
        guard let firstChild = sectionNode.orderedChildren.first else { return nil }
        let value = firstChild.value
        return value.isEmpty ? nil : value
    }

    private func buildArrayOfObjectsSection(named sectionName: String) -> [Any]? {
        guard let sectionNode = sectionNodeProvider(sectionName) else { return nil }

        var items: [[String: Any]] = []
        for child in sectionNode.orderedChildren {
            var entry: [String: Any] = [:]
            for grandchild in child.orderedChildren {
                if let nested = nodeValueProvider(grandchild) {
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
        guard let sectionNode = sectionNodeProvider(sectionName) else { return nil }
        let children = sectionNode.orderedChildren
        guard !children.isEmpty else { return nil }

        let hasNamedChild = children.contains { !$0.name.isEmpty }

        if hasNamedChild {
            var dictionary: [String: Any] = [:]
            for child in children where !child.name.isEmpty {
                if let value = nodeValueProvider(child) {
                    dictionary[child.name] = value
                } else if !child.value.isEmpty {
                    dictionary[child.name] = child.value
                }
            }
            return dictionary.isEmpty ? nil : dictionary
        } else {
            let arrayValues = children.compactMap { node -> Any? in
                if let value = nodeValueProvider(node) {
                    return value
                }
                return node.value.isEmpty ? nil : node.value
            }
            return arrayValues.isEmpty ? nil : arrayValues
        }
    }
}
