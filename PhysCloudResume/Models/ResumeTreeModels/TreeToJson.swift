//
//  TreeToJson.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/2/25.
//

import Foundation

class TreeToJson {
    private let rootNode: TreeNode

    init?(rootNode: TreeNode?) {
        if let myRoot = rootNode {
            self.rootNode = myRoot
        } else {
            return nil
        }
    }

    /// Retrieves the correct function to build JSON for a given section type.

    func buildJsonString() -> String {
        var jsonComponents: [String] = []
        for sectionKey in JsonMap.sectionKeyToTypeDict.keys {
            guard let sectionType = JsonMap.sectionKeyToTypeDict[sectionKey] else {
                return ""
            }
            let stringFunc = stringFunction(
                for: sectionType
            )

            let result = stringifySection(sectionName: sectionKey, stringFn: stringFunc)
            if !result.isEmpty {
                jsonComponents.append(result)
            } else { print("empty \(sectionKey)") }
        }

        return "{\n\(jsonComponents.joined(separator: ",\n"))\n}"
    }

    private func stringifySection(
        sectionName: String, stringFn: (String) -> String?, keyOne _: String = "title",
        keyTwo _: String = "description"
    ) -> String {
        var mySection = ""
        if let content = stringFn(sectionName) {
            mySection = "\"\(sectionName)\": \(content)"
        }

        return mySection
    }

    func stringFunction(for sectionType: SectionType) -> (String) -> String? {
        switch sectionType {
        case .object:
            return stringObjectSection
        case .array:
            return stringArraySection
        case .complex:
            return stringComplexSection
        case .string:
            return stringStringSection
        case let .twoKeyObjectArray(keyOne, keyTwo):
            return { sectionName in
                self.stringTwoKeyObjectsSection(sectionName, keyOne: keyOne, keyTwo: keyTwo)
            }
        case .fontSizes:
            return stringFontSizes
        }
    }

    func stringFontSizes(sectionName _: String) -> String? {
        let fontNodes = rootNode.resume.fontSizeNodes
        let fontStrings = fontNodes.compactMap { node in
            "\"\(node.key)\": \"\(node.fontString)\""
        }

        return "{\n \(fontStrings.joined(separator: ",\n")) \n}"
    }

    /// Builds a JSON array from a section that contains an array of strings.
    func stringArraySection(for sectionName: String) -> String? {
        guard let sectionNode = rootNode.children?.first(where: { $0.name == sectionName }),
              let children = sectionNode.children, !children.isEmpty
        else { return nil }

        let jsonArray = children
            .sorted { $0.myIndex < $1.myIndex }
            .compactMap { child in
                guard !child.value.isEmpty else { return nil }
                return "    \"\(escape(child.value))\""
            }
            .joined(separator: ",\n")

        return jsonArray.isEmpty ? nil : "[\n\(jsonArray)\n]"
    }

    /// Builds a JSON object from a section whose children are key-value pairs.
    func stringObjectSection(for sectionName: String) -> String? {
        guard let sectionNode = rootNode.children?.first(where: { $0.name == sectionName }),
              let children = sectionNode.children, !children.isEmpty
        else { return nil }

        let keyValuePairs =
            children
                .sorted { $0.myIndex < $1.myIndex }
                .compactMap { child -> String? in
                    let value = escape(child.value)
                    return "\"\(child.name)\": \"\(value)\""
                }
                .joined(separator: ",\n")

        return "{\n\(keyValuePairs)\n}"
    }

    /// Builds a JSON array for sections that have more complex children (objects built from their subtrees).
    func stringComplexSection(for sectionName: String) -> String? {
        guard let sectionNode = rootNode.children?.first(where: { $0.name == sectionName }),
              let nodes = sectionNode.children?.sorted(by: { $0.myIndex < $1.myIndex }),
              !nodes.isEmpty
        else { return nil }
        var leader = "[\n"
        var trailer = "\n]"
        let objects = nodes.compactMap { node -> String? in

            if !node.name.isEmpty {
                leader = "{\n"
                trailer = "\n}"
            }
            if node.hasChildren {
                if let sortedChildren = node.children?.sorted(by: { $0.myIndex < $1.myIndex }) {
                    let stringChildren = sortedChildren.compactMap { child -> String? in
                        if !child.hasChildren {
                            if child.name.isEmpty {
                                return "\"\(escape(child.value))\""
                            } else {
                                return "\"\(escape(child.name))\": \"\(escape(child.value))\""
                            }
                        } else {
                            let nested = stringObjectSection(from: child)
                            return "\"\(escape(child.name))\": \(nested)"
                        }
                    }

                    //                guard !stringChildren.isEmpty else { return nil }

                    let items = stringChildren.joined(separator: ",\n")
                    if node.name.isEmpty {
                        return "{\n" + items + "\n}"
                    } else {
                        return "\"\(node.name)\": {\n \(items) \n}"
                    }
                }

                else {
                    print("sorted children prob")
                    return nil
                }
            } else {
                return "\"\(node.name)\": \"\(escape(node.value))\""
            }
        }

        return leader + objects.joined(separator: ",\n") + trailer
    }

    func stringTwoKeyObjectsSection(
        _ sectionName: String, keyOne: String = "name", keyTwo: String = "value"
    ) -> String? {
        guard let sectionNode = rootNode.children?.first(where: { $0.name == sectionName }) else {
            print("export problem: \(sectionName) is expected, but not found")
            return nil
        }

        let items = sectionNode.children?.sorted { $0.myIndex < $1.myIndex }
            .compactMap { child -> String? in
                if child.name.isEmpty, !child.value.isEmpty {
                    return "\"\(escape(child.value))\""
                } else if !child.name.isEmpty {
                    let valueone = child.name
                    let valuetwo = child.value

                    return """
                    {
                        "\(keyOne)": "\(escape(valueone))",
                        "\(keyTwo)": "\(escape(valuetwo))"
                    }
                    """
                } else {
                    print("!&! empty node found")
                    return nil
                }
            }
            .joined(separator: ",\n")

        return (items?.isEmpty == false) ? "[\n" + items! + "\n]" : nil
    }

    /// Builds a dictionary representation from a node’s name and children.

    /// Recursively builds a JSON object from a node.
    func stringObjectSection(from node: TreeNode) -> String {
        if let children = node.children, !children.isEmpty {
            var arrayFlag = false
            let items = children.sorted { $0.myIndex < $1.myIndex }
                .compactMap { child -> String? in
                    if child.children?.isEmpty ?? true {
                        let value = child.value
                        if child.name.isEmpty {
                            arrayFlag = true
                            return "\"\(escape(value))\""
                        } else {
                            return "\"\(child.name)\": \"\(escape(value))\""
                        }
                    } else {
                        let nested = stringObjectSection(from: child)
                        return "\"\(child.name)\": \(nested)"
                    }
                }
                .joined(separator: ",\n")

            return arrayFlag ? "[\n" + items + "\n]" : "{\n" + items + "\n}"
        }
        let value = node.value
        return "\"\(escape(value))\""
    }

    func stringStringSection(for sectionName: String) -> String? {
        if let node = rootNode.children?.first(where: { $0.name == sectionName }),
           let child = node.children?.first
        {
            let value = child.value
            if !value.isEmpty {
                return "\"\(escape(value))\""
            }
        }
        return nil
    }

    private func escape(_ string: String) -> String {
        return string.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
