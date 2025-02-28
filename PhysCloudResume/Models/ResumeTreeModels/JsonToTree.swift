//
//  JsonToTree.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/4/25.
//

import Foundation
import OrderedCollections

class JsonToTree {
    private let res: Resume
    var json: OrderedDictionary<String, Any>
    private var treeKeys: [String] = []

    init?(resume: Resume, rawJson: String) {
        res = resume
        guard let orderedDictJson = JsonToTree.parseUnwrapJson(rawJson) else {
            print("Error converting JSON content")

            return nil
        }

        json = orderedDictJson
        treeKeys = json.keys.filter { !JsonMap.specialKeys.contains($0) }
    }

    private func isInEditor(_ key: String) -> Bool {
        return res.importedEditorKeys.contains(key)
    }

    private static func parseUnwrapJson(_ rawJson: String) -> OrderedDictionary<String, Any>? {
        guard let jsonData = rawJson.data(using: .utf8) else {
            print("Error converting JSON string to Data")
            return nil
        }

        var parser = JSONParser(bytes: Array(jsonData))

        do {
            let jsonValue = try parser.parse()
            let unwrappedJson = try jsonValue.unwrap()
            if let orderedJsonDict = unwrappedJson as? OrderedDictionary<String, Any> {
                return orderedJsonDict
            } else {
                return nil
            }
        } catch {
            print("Error during JSON parsing/unwrapping: \(error)")
            return nil
        }
    }

    func buildTree() -> TreeNode? {
        let rootNode = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: res)
        TreeNode.childIndexer = 0
        guard res.needToTree else {
            fatalError("Extra run attempted – why is there an extra tree rebuild")
        }
        res.needToTree = false
        parseSpecialKeys()
        for key in treeKeys {
            if let sectionType = JsonMap.sectionKeyToTypeDict[key] {
                print("DEBUG: Building tree for key='\(key)' with type=\(sectionType)")
                let function = treeFunction(for: sectionType)
                function(key, rootNode)
            } else {
                print("DEBUG: No mapping found for key='\(key)'")
            }
        }
        processKeyLabels()
        return rootNode
    }

    private func parseInclude(key: String) -> Bool {
        if let myString = json[key] as? String {
            print("myString detected as \(myString)")
            if myString == "true" {
                print("myString matched true")
                return true
            }
        }
        return false
    }

    private func parseSpecialKeys() {
        res.fontSizeNodes = parseFontSizeSection(key: "font-sizes")
        res.includeFonts = parseInclude(key: "include-fonts")
        res.importedEditorKeys = parseStringArray(key: "keys-in-editor")
        print("!!!! importedKeys: \(res.importedEditorKeys)")
    }

    private func processKeyLabels() {
        if let labelDict = json["section-labels"] as? OrderedDictionary<String, Any> {
            for key in labelDict.keys {
                if let value = labelDict[key] { // Correct dictionary access
                    res.keyLabels[key] = value as? String ?? "Error!" // Assigning the value correctly
                    print("labeltime: key:\(key) label:\(value) value:\(labelDict)")
                }
            }
        } else {
            print("label cast problem")
        }
    }

    private func parseFontSizeSection(key: String) -> [FontSizeNode] {
        guard res.needToFont else {
            fatalError("Extra font size run attempted – unexpected redundant execution")
        }
        res.needToFont = false
        guard let fontArray = json[key] as? OrderedDictionary<String, Any>
        else {
            print("Font sizes could not be cast")
            return []
        }

        let parsedNodes = fontArray.compactMap { myKey, myValue -> FontSizeNode? in
            let fontString = myValue
            print("Adding FontSizeNode: key = \(myKey), fontString = \(fontString)")
            return FontSizeNode(key: myKey, fontString: fontString as? String ?? "")
        }

        print("Completed parsing font sizes. Count: \(parsedNodes.count)")
        return parsedNodes
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
        case let .twoKeyObjectArray(keyOne, keyTwo):
            return { sectionName, parent in
                self.treeTwoKeyObjectsSection(key: sectionName, parent: parent, keyOne: keyOne, keyTwo: keyTwo)
            }
        case .fontSizes:
            return { _, _ in }
        }
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

        // 1) If the value is an OrderedDictionary<String, Any> (a single dictionary).
        if let dict = json[key] as? OrderedDictionary<String, Any> {
            print("\(key) is an OrderedDictionary")
            buildSubtree(from: dict, parent: sectionNode, inEditor: inEditor)
            return
        }

        // 2) If the value is an array of OrderedDictionary<String, Any>.
        if let arrayOfODicts = json[key] as? [OrderedDictionary<String, Any>] {
            print("\(key) is an array of OrderedDictionaries with count \(arrayOfODicts.count)")
            for (index, subDict) in arrayOfODicts.enumerated() {
                let itemTitle = "\(subDict["journal"] ?? key) · \(subDict["year"] ?? String(index + 1))" // or pick a field from subDict if you prefer
                let itemNode = sectionNode.addChild(
                    TreeNode(name: itemTitle, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
                )
                buildSubtree(from: subDict, parent: itemNode, inEditor: inEditor)
            }
            return
        }

        // 3) Catch-all / fallback so you actually see a console message if everything else fails.
        print("Warning: \(key) is missing or not in expected format (not a dictionary or array-of-dictionaries).")
    }

    private func buildSubtree(from dict: OrderedDictionary<String, Any>, parent: TreeNode, inEditor: Bool) {
        for (subKey, subValue) in dict {
            if let subDict = subValue as? OrderedDictionary<String, Any> {
                let childNode = parent.addChild(
                    TreeNode(name: subKey, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res)
                )
                buildSubtree(from: subDict, parent: childNode, inEditor: inEditor) // 🔥 Recursive helper function call
            } else if let subArray = subValue as? [String] {
                let arrayTitleNode = parent.addChild(TreeNode(name: subKey, value: "", inEditor: inEditor, status: .isNotLeaf, resume: res))
                treeNodesStringArray(strings: subArray, parent: arrayTitleNode, inEditor: inEditor)
            } else if let subString = subValue as? String {
                parent.addChild(
                    TreeNode(
                        name: subKey,
                        value: subString,
                        inEditor: inEditor, status: .saved,
                        resume: res
                    )
                )
            } else {
                print("Warning: Unexpected type for key \(subKey)")
            }
        }
    }

    private func treeTwoKeyObjectsSection(key: String, parent: TreeNode, keyOne: String, keyTwo: String) {
        guard let sectionArray = json[key] as? [OrderedDictionary<String, Any>] else {
            print("Warning: \(key) is missing or not in expected format")
            return
        }

        let sectionNode = parent.addChild(
            TreeNode(name: key, value: "", inEditor: isInEditor(key), status: .isNotLeaf, resume: res)
        )

        for element in sectionArray {
            guard let valueOne = element[keyOne] as? String,
                  let valueTwo = element[keyTwo] as? String
            else {
                print("Warning: Skipping malformed entry in \(key)")
                continue
            }
            // Add the node with name = valueOne, value = valueTwo
            sectionNode.addChild(
                TreeNode(name: valueOne, value: valueTwo, inEditor: isInEditor(key), status: .isNotLeaf, resume: res)
            )
        }
    }

    private func treeStringSection(key: String, parent: TreeNode) {
        if let sectionString = json[key] as? String {
            let sectionNode = parent.addChild(
                TreeNode(name: key, value: "", inEditor: isInEditor(key), status: .isNotLeaf, resume: res))
            sectionNode.addChild(TreeNode(name: "", value: sectionString, inEditor: isInEditor(key), status: .saved, resume: res))
        }
    }

    private func treeStringObjectSection(key: String, parent: TreeNode) {
        if let sectionDict = json[key] as? OrderedDictionary<String, Any> {
            let sectionNode = parent.addChild(
                TreeNode(name: key, value: "", inEditor: isInEditor(key), status: .isNotLeaf, resume: res))
            for (key, myValue) in sectionDict {
                guard let valueString = myValue as? String else {
                    print("\(key) json error")
                    return
                }
                sectionNode.addChild(
                    TreeNode(name: key, value: valueString, inEditor: isInEditor(key), status: .saved, resume: res))
            }
        } else {
            print("!!!!Warning: \(key)  missing or not the expected type.")
        }
    }
}
