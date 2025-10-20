//
//  ResumeTemplateDataBuilder.swift
//  Sprung
//

import Foundation
import OrderedCollections

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
        let manifest = resume.template.flatMap { template in
            TemplateManifestLoader.manifest(for: template)
        }
        let implementation = Implementation(resume: resume, rootNode: rootNode, manifest: manifest)
        return implementation.buildContext()
    }
}

// MARK: - Private Implementation

private final class Implementation {
    let resume: Resume
    let rootNode: TreeNode
    let manifest: TemplateManifest?
    private let fontScaler = FontSizeScaler()
    private lazy var valueNormalizer = SectionValueNormalizer(
        resume: resume,
        manifest: manifest,
        fontScaler: fontScaler
    )
    private lazy var titleRenderer = TitleTemplateRenderer()
    private lazy var descriptorValidator = DescriptorValueValidator()
    private lazy var sectionBuilder: SectionBuilder = {
        SectionBuilder(
            resume: resume,
            sectionNodeProvider: { self.sectionNode(named: $0) },
            nodeValueProvider: { self.buildNodeValue($0) }
        )
    }()
    private lazy var descriptorInterpreter: DescriptorInterpreter = {
        DescriptorInterpreter(
            resume: resume,
            manifest: manifest,
            fontScaler: fontScaler,
            valueNormalizer: valueNormalizer,
            titleRenderer: titleRenderer,
            validator: descriptorValidator,
            sectionNodeProvider: { self.sectionNode(named: $0) },
            nodeValueProvider: { self.buildNodeValue($0) },
            fontSizesFallback: { self.buildFontSizesSection() },
            rawSectionBuilder: { sectionName, sectionType in
                self.sectionBuilder.buildSection(named: sectionName, type: sectionType)
            }
        )
    }()

    init(resume: Resume, rootNode: TreeNode, manifest: TemplateManifest?) {
        self.resume = resume
        self.rootNode = rootNode
        self.manifest = manifest
    }

    func buildContext() -> [String: Any] {
        var context: [String: Any] = [:]

        // Get keys from tree nodes
        var keys = rootNode.orderedChildren.map { $0.name }

        // Also include sections from manifest that have special behaviors
        if let manifest = manifest {
            for (sectionKey, section) in manifest.sections {
                if let behavior = section.behavior,
                   [.styling, .fontSizes].contains(behavior),
                   !keys.contains(sectionKey) {
                    keys.append(sectionKey)
                }
            }
        }

        let orderedKeys = Self.orderedKeys(from: keys, manifest: manifest)

        for sectionKey in orderedKeys {
            guard let value = buildSection(named: sectionKey) else { continue }
            context[sectionKey] = value
        }

        // Fallback for editor keys when the node is absent but metadata exists.
        if context["keys-in-editor"] == nil, !resume.importedEditorKeys.isEmpty {
            context["keys-in-editor"] = resume.importedEditorKeys
        }

        if let manifest {
            applySectionVisibility(to: &context, manifest: manifest)
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
           let value = descriptorInterpreter.buildSection(named: sectionName, section: section) {
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
                let normalized = valueNormalizer.normalize(dictionary, for: .fontSizes)
                Logger.debug("raw fontsizes: \(dictionary)")
                if valueNormalizer.isEmpty(normalized) == false {
                    return normalized
                }
            }
            if let fallback = buildFontSizesSection() {
                return valueNormalizer.normalize(fallback, for: .fontSizes)
            }
            return nil

        case .includeFonts:
            if let sectionNode,
               let value = buildNodeValue(sectionNode) {
                let normalized = valueNormalizer.normalize(value, for: .includeFonts)
                if valueNormalizer.isEmpty(normalized) == false {
                    return normalized
                }
            }
            let includeFonts = resume.includeFonts ? "true" : "false"
            return valueNormalizer.normalize(includeFonts, for: .includeFonts)

        case .editorKeys:
            if let sectionNode,
               let value = buildNodeValue(sectionNode) {
                let normalized = valueNormalizer.normalize(value, for: .editorKeys)
                if valueNormalizer.isEmpty(normalized) == false {
                    return normalized
                }
            }
            guard resume.importedEditorKeys.isEmpty == false else { return nil }
            return valueNormalizer.normalize(resume.importedEditorKeys, for: .editorKeys)

        case .styling:
            // Build the styling section including fontSizes
            var styling: [String: Any] = [:]
            if let rawFontSizes = buildFontSizesSection() ?? valueNormalizer.defaultFontSizes() {
                let scaledFontSizes = fontScaler.scaleFontSizes(rawFontSizes)
                styling["fontSizes"] = scaledFontSizes
                Logger.debug("ResumeTemplateDataBuilder: using scaled fontSizes => \(scaledFontSizes)")
            }
            if let margins = valueNormalizer.defaultPageMargins() {
                styling["pageMargins"] = margins
                Logger.debug("ResumeTemplateDataBuilder: using pageMargins => \(margins)")
            }
            if let includeFontsOverride = valueNormalizer.defaultIncludeFonts() {
                styling["includeFonts"] = includeFontsOverride ? "true" : "false"
                Logger.debug("ResumeTemplateDataBuilder: using includeFonts override => \(includeFontsOverride)")
            } else if resume.includeFonts {
                styling["includeFonts"] = "true"
                Logger.debug("ResumeTemplateDataBuilder: includeFonts set from resume flag")
            }
            return styling.isEmpty ? nil : styling

        case .metadata, .applicantProfile:
            return nil
        }
    }

    private func buildSection(named sectionName: String, type: SectionType) -> Any? {
        switch type {
        case .fontSizes:
            guard let fontSizes = buildFontSizesSection() else { return nil }
            return fontScaler.scaleFontSizes(fontSizes)
        default:
            return sectionBuilder.buildSection(named: sectionName, type: type)
        }
    }

    // MARK: Section Builders

    private func applySectionVisibility(
        to context: inout [String: Any],
        manifest: TemplateManifest
    ) {
        var visibility = manifest.sectionVisibilityDefaults ?? [:]
        let overrides = resume.sectionVisibilityOverrides
        for (key, value) in overrides {
            visibility[key] = value
        }
        guard visibility.isEmpty == false else { return }

        for (sectionKey, isVisible) in visibility {
            let boolKey = "\(sectionKey)Bool"
            let baseVisible: Bool
            if let numeric = context[boolKey] as? NSNumber {
                baseVisible = numeric.boolValue
            } else if let flag = context[boolKey] as? Bool {
                baseVisible = flag
            } else if let value = context[sectionKey] {
                baseVisible = truthy(value)
            } else {
                baseVisible = false
            }
            context[boolKey] = baseVisible && isVisible
        }
    }

    private func buildFontSizesSection() -> [String: String]? {
        fontScaler.buildFontSizes(from: resume.fontSizeNodes)
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

    private func truthy(_ value: Any) -> Bool {
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return string.isEmpty == false
        case let array as [Any]:
            return array.isEmpty == false
        case let dict as [String: Any]:
            return dict.isEmpty == false
        case let ordered as OrderedDictionary<String, Any>:
            return ordered.isEmpty == false
        default:
            return true
        }
    }
}
