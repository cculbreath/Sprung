//
//  ResumeTextSnapshotBuilder.swift
//  Sprung
//
//  Shared utility that walks a Resume's TreeNode tree and produces a
//  markdown-style plain-text snapshot suitable for LLM prompts.
//

import Foundation

enum ResumeTextSnapshotBuilder {

    /// Build a plain-text representation of the resume by walking the tree.
    /// Produces a clean, readable text snapshot suitable for LLM analysis
    /// without requiring the full Mustache template rendering pipeline.
    static func buildSnapshot(resume: Resume) -> String {
        guard let root = resume.rootNode else { return "(empty resume)" }

        var lines: [String] = []

        guard let sections = root.children?.sorted(by: { $0.myIndex < $1.myIndex }) else {
            return "(no sections)"
        }

        for section in sections {
            let sectionName = section.displayLabel
            lines.append("## \(sectionName)")

            if let children = section.children?.sorted(by: { $0.myIndex < $1.myIndex }) {
                for entry in children {
                    renderNode(entry, into: &lines, indent: 1)
                }
            } else if !section.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(section.value)
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Recursively render a tree node into text lines with indentation.
    private static func renderNode(_ node: TreeNode, into lines: inout [String], indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        let name = node.displayLabel
        let value = node.value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let children = node.children?.sorted(by: { $0.myIndex < $1.myIndex }), !children.isEmpty {
            // Container node: render name as header, then children
            lines.append("\(prefix)### \(name)")
            if !value.isEmpty {
                lines.append("\(prefix)\(value)")
            }
            for child in children {
                renderNode(child, into: &lines, indent: indent + 1)
            }
        } else {
            // Leaf node
            if !value.isEmpty {
                if name != value {
                    lines.append("\(prefix)- \(name): \(value)")
                } else {
                    lines.append("\(prefix)- \(value)")
                }
            }
        }
    }
}
