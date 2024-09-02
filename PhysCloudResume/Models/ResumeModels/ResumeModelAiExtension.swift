
//
//  ResumeModelAiExtension.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/24/24.
//



import Foundation
import SwiftData

// Example Usage:

//        struct ContentView: View {
//            @Environment(\.modelContext) private var modelContext
//
//            var body: some View {
//                Button("Update TreeNodes") {
//                    do {
//                        let jsonFileURL = URL(fileURLWithPath: "/path/to/your/json/file.json")
//                        try TreeNode.updateValues(from: jsonFileURL, using: modelContext)
//                        print("TreeNode values updated successfully.")
//                    } catch {
//                        print("Error updating TreeNode values: \(error)")
//                    }
//                }
//            }
//        }

extension TreeNode {
    static func traverseAndExportNodes(node: TreeNode, currentPath: String = "")
        -> [[String: String]]
    {
        var result: [[String: String]] = []
        var newPath: String
        // Construct the current tree path
        if node.parent == nil {
            newPath = "Resume"
        }
        else {
             newPath =
            currentPath.isEmpty ? node.name : "\(currentPath) > \(node.name)"
        }
        // If the node's status is .aiToReplace, add it to the result array
        if node.status == .aiToReplace {
            if (node.name != "" && node.value != ""){

            }


            let nodeData: [String: String] = [
                "id": node.id,
                "value": node.value,
                "tree_path": newPath,
            ]
            result.append(nodeData)
        }

        // Recursively traverse the children
        for child in node.children ?? [] {
            let childResults = traverseAndExportNodes(
                node: child, currentPath: newPath)
            result.append(contentsOf: childResults)
        }

        return result
    }

    /// Updates the values of TreeNode objects based on the provided JSON file.
    /// - Parameters:
    ///   - jsonFileURL: The URL of the JSON file containing the array of {id: String, value: String} objects.
    ///   - context: The SwiftData context used to fetch and update the TreeNode objects.
    /// - Throws: An error if reading the JSON file, parsing JSON, or saving the context fails.
    static func updateValues(from jsonFileURL: URL, using context: ModelContext)
        throws
    {
        // Load JSON data from the provided file URL
        let jsonData = try Data(contentsOf: jsonFileURL)

        // Parse JSON data into an array of dictionaries
        guard
            let jsonArray = try JSONSerialization.jsonObject(
                with: jsonData, options: []) as? [[String: String]]
        else {
            print("Failed to parse JSON.")
            return
        }

        // Iterate over the array and update corresponding TreeNodes
        for jsonObject in jsonArray {
            if let id = jsonObject["id"], let newValue = jsonObject["value"] {
                // Fetch the corresponding TreeNode from the SwiftData store manually
                let fetchRequest = FetchDescriptor<TreeNode>(
                    predicate: #Predicate { $0.id == id }
                )

                if let node = try context.fetch(fetchRequest).first {
                    // Update the value of the TreeNode
                    node.value = newValue
                } else {
                    print("TreeNode with id \(id) not found.")
                }
            } else {
                print("Invalid JSON object: \(jsonObject)")
            }
        }

        // Save the context to persist changes
        try context.save()
    }
}
