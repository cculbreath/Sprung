//
//  ResumeTemplateDataBuilder.swift
//  PhysCloudResume
//
//  Created by Codex Agent on 10/23/25.
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
        if let manifestKind = manifest?.section(for: sectionName)?.type,
           let sectionType = SectionType(manifestKind: manifestKind, key: sectionName) {
            return buildSection(named: sectionName, type: sectionType)
        }

        return nodeValue(named: sectionName)
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
        if sectionName == "keys-in-editor",
           !resume.importedEditorKeys.isEmpty {
            return resume.importedEditorKeys
        }

        guard let sectionNode = sectionNode(named: sectionName) else { return nil }

        let values = sectionNode.orderedChildren
            .map(\.value)
            .filter { !$0.isEmpty }

        return values.isEmpty ? nil : values
    }

    private func buildStringSection(named sectionName: String) -> Any? {
        if sectionName == "include-fonts" {
            return resume.includeFonts ? "true" : "false"
        }

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

    // MARK: Helpers

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
}
