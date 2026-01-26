//
//  AIStatusIcon.swift
//  Sprung
//
//  Icon-based AI status indicator. Every attribute/collection shows
//  an always-colored icon indicating its AI review mode.
//

import SwiftUI

/// Icon modes for AI status display
enum AIIconMode: Equatable {
    case iteratedCollection   // film.stack, indigo - Collection with [] iterate
    case iteratedMember       // inset.filled.bottomhalf.rectangle, indigo (hierarchical)
    case bundledCollection    // circle.hexagongrid.circle, purple - Collection with .* bundle
    case bundledMember        // custom.bundled.member, purple - Child in bundled collection
    case unset                // sparkles, gray (primary) - No AI assignment
    case solo                 // target, teal - Individual node marked for AI

    var symbolName: String {
        switch self {
        case .iteratedCollection: return "film.stack"
        case .iteratedMember: return "inset.filled.bottomhalf.rectangle"
        case .bundledCollection: return "circle.hexagongrid.circle"
        case .bundledMember: return "custom.bundled.member"
        case .unset: return "sparkles"
        case .solo: return "target"
        }
    }

    var color: Color {
        switch self {
        case .iteratedCollection, .iteratedMember: return .indigo
        case .bundledCollection, .bundledMember: return .purple
        case .unset: return .primary
        case .solo: return .teal
        }
    }

    var usesHierarchical: Bool {
        switch self {
        case .iteratedMember: return true
        default: return false
        }
    }

    /// Whether this is a custom symbol from the asset catalog (not SF Symbols)
    var isCustomSymbol: Bool {
        self == .bundledMember
    }

    var helpText: String {
        switch self {
        case .iteratedCollection: return "Iterate: N reviews (one per entry)"
        case .iteratedMember: return "Included in iterate review (per entry)"
        case .bundledCollection: return "Bundle: All entries combined into 1 review"
        case .bundledMember: return "Included in bundle review (all combined)"
        case .unset: return "Click to configure AI review"
        case .solo: return "Solo: Just this one item"
        }
    }
}

/// Result of icon resolution for a node
struct AIIconResolution: Equatable {
    let primary: AIIconMode
    let secondary: AIIconMode?
    /// true = arrow between icons (member→collection), false = side by side
    let showArrow: Bool

    var isDual: Bool { secondary != nil }

    static func single(_ mode: AIIconMode) -> AIIconResolution {
        AIIconResolution(primary: mode, secondary: nil, showArrow: false)
    }

    static func dual(_ a: AIIconMode, _ b: AIIconMode, arrow: Bool) -> AIIconResolution {
        AIIconResolution(primary: a, secondary: b, showArrow: arrow)
    }
}

// MARK: - AIIconImage (plain view for Menu labels)

/// Plain icon image — no Button wrapper. Use inside Menu labels where
/// Button nesting causes SwiftUI to override foreground colors.
struct AIIconImage: View {
    let mode: AIIconMode
    var size: CGFloat = 14

    var body: some View {
        if mode.isCustomSymbol {
            Image("custom.bundled.member")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(mode.color)
                .font(.system(size: size))
        } else {
            Image(systemName: mode.symbolName)
                .symbolRenderingMode(mode.usesHierarchical ? .hierarchical : .monochrome)
                .foregroundStyle(mode.color)
                .font(.system(size: size))
        }
    }
}

// MARK: - AIStatusIcon (Button wrapper for standalone use)

/// Clickable AI status icon — wraps AIIconImage in a Button.
/// Use standalone (not inside Menu labels) where you need a tap handler.
struct AIStatusIcon: View {
    let mode: AIIconMode
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AIIconImage(mode: mode)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.helpText)
    }
}

// MARK: - Resolved Icon View

/// Renders the correct icon(s) for an AIIconResolution.
/// Uses plain AIIconImage — safe for use inside Menu labels.
struct ResolvedAIIcon: View {
    let resolution: AIIconResolution

    var body: some View {
        if resolution.isDual {
            HStack(spacing: resolution.showArrow ? 1 : 2) {
                AIIconImage(mode: resolution.primary)
                    .padding(4)

                if resolution.showArrow {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let secondary = resolution.secondary {
                    AIIconImage(mode: secondary)
                        .padding(4)
                }
            }
        } else {
            AIIconImage(mode: resolution.primary)
                .padding(4)
        }
    }
}

// MARK: - Mode Detection

/// Determines the appropriate AIIconMode for a tree node
struct AIIconModeResolver {

    /// Full resolution: returns primary + optional secondary icon with arrow info
    static func resolve(for node: TreeNode) -> AIIconResolution {
        // 1. Section/collection with its own AI config
        let hasBundled = node.bundledAttributes?.isEmpty == false
        let hasIterated = node.enumeratedAttributes?.isEmpty == false

        if hasBundled && hasIterated {
            // Collection+Collection: both icons, NO arrow
            return .dual(.bundledCollection, .iteratedCollection, arrow: false)
        }
        if hasIterated && !hasBundled {
            return .single(.iteratedCollection)
        }
        if hasBundled && !hasIterated {
            return .single(.bundledCollection)
        }

        // 2. Nested container: both a member (of parent's config) AND a collection (has children)
        if let dual = resolveDualContainerMode(for: node) {
            return dual
        }

        // 3. Entry under a section with AI config
        if let entryMode = resolveEntryMode(for: node) {
            return .single(entryMode)
        }

        // 4. Leaf member of an AI-reviewed group
        if let leafMode = resolveLeafMemberMode(for: node) {
            return .single(leafMode)
        }

        // 5. Solo
        if node.status == .aiToReplace {
            return .single(.solo)
        }

        // 6. Default
        return .single(.unset)
    }

    /// Shorthand for views that only need a single mode (picks primary)
    static func detectSingleMode(for node: TreeNode) -> AIIconMode {
        resolve(for: node).primary
    }

    // MARK: - Dual Container Detection

    /// A container that is both a member (referenced in grandparent's AI config)
    /// AND a collection (has children whose review mode is determined by suffix).
    ///
    /// Example: `highlights` under `work[].highlights`
    ///   - iteratedMember (highlights is in work's enumeratedAttributes)
    ///   - bundledCollection (no [] suffix → children are bundled together)
    ///   - Shows: [iteratedMember] → [bundledCollection] with arrow
    private static func resolveDualContainerMode(for node: TreeNode) -> AIIconResolution? {
        // Must have children to be a collection
        guard !node.orderedChildren.isEmpty else { return nil }

        // Must have a grandparent (collection level) with AI config
        guard let grandparent = node.parent?.parent else { return nil }

        let name = node.name.isEmpty ? node.displayLabel : node.name
        let nameWithSuffix = name + "[]"

        // Determine member mode: how does this container relate to the grandparent's config?
        let memberMode: AIIconMode
        if grandparent.enumeratedAttributes?.contains(name) == true ||
           grandparent.enumeratedAttributes?.contains(nameWithSuffix) == true {
            memberMode = .iteratedMember
        } else if grandparent.bundledAttributes?.contains(name) == true ||
                  grandparent.bundledAttributes?.contains(nameWithSuffix) == true {
            memberMode = .bundledMember
        } else {
            return nil // Not referenced in grandparent's AI config
        }

        // Determine collection mode: how are this container's children treated?
        // With [] suffix on the attribute name → children are iterated individually
        // Without [] suffix → children are bundled together
        let collectionMode: AIIconMode
        if grandparent.enumeratedAttributes?.contains(nameWithSuffix) == true ||
           grandparent.bundledAttributes?.contains(nameWithSuffix) == true {
            collectionMode = .iteratedCollection
        } else {
            collectionMode = .bundledCollection
        }

        // Member→Collection with arrow (member on left, collection on right)
        return .dual(memberMode, collectionMode, arrow: true)
    }

    // MARK: - Entry Mode Detection

    /// An entry (direct child of a section) whose parent section has AI config.
    /// e.g., a work experience entry under work[] → iteratedMember
    private static func resolveEntryMode(for node: TreeNode) -> AIIconMode? {
        guard let parent = node.parent else { return nil }
        // Must have children (entries are containers)
        guard !node.orderedChildren.isEmpty else { return nil }

        let hasBundled = parent.bundledAttributes?.isEmpty == false
        let hasIterated = parent.enumeratedAttributes?.isEmpty == false

        guard hasBundled || hasIterated else { return nil }

        // Prefer iterated if section has both modes
        if hasIterated {
            return .iteratedMember
        }
        return .bundledMember
    }

    // MARK: - Leaf Member Detection

    /// A leaf node that participates in an AI-reviewed group.
    private static func resolveLeafMemberMode(for node: TreeNode) -> AIIconMode? {
        guard let parent = node.parent else { return nil }

        // Case 1: Scalar array child (parent has bundledAttributes["*"] or enumeratedAttributes["*"])
        if parent.bundledAttributes?.contains("*") == true {
            return .bundledMember
        }
        if parent.enumeratedAttributes?.contains("*") == true {
            return .iteratedMember
        }

        // Case 2: Scalar attribute under a collection entry
        // e.g., "name" field under skill entry where skills section has bundledAttributes["name"]
        // node.parent = entry, node.parent.parent = section (collection)
        if node.orderedChildren.isEmpty, let collection = parent.parent {
            let nodeName = node.name.isEmpty ? node.displayLabel : node.name

            if collection.bundledAttributes?.contains(nodeName) == true {
                return .bundledMember
            }
            if collection.enumeratedAttributes?.contains(nodeName) == true {
                return .iteratedMember
            }
        }

        // Case 3: Child of a nested array container
        // e.g., "Swift" keyword under "keywords" where skills has enumeratedAttributes["keywords"]
        // node.parent = keywords, node.parent.parent = entry, node.parent.parent.parent = section
        if let entry = parent.parent, let collection = entry.parent {
            let parentName = parent.name.isEmpty ? parent.displayLabel : parent.name
            let parentNameWithSuffix = parentName + "[]"

            // With [] suffix → children are iterated
            if collection.enumeratedAttributes?.contains(parentNameWithSuffix) == true ||
               collection.bundledAttributes?.contains(parentNameWithSuffix) == true {
                return .iteratedMember
            }

            // Without suffix → children are bundled
            if collection.enumeratedAttributes?.contains(parentName) == true ||
               collection.bundledAttributes?.contains(parentName) == true {
                return .bundledMember
            }
        }

        return nil
    }

    /// Check if a node should show an icon at all
    static func shouldShowIcon(for node: TreeNode) -> Bool {
        guard node.parent != nil else { return false }
        return true
    }
}

// MARK: - String Formatting

extension String {
    /// Convert camelCase to Title Case: "startDate" → "Start Date", "highlights" → "Highlights"
    var titleCased: String {
        guard !isEmpty else { return self }
        if contains(" ") { return self }
        var result = ""
        for (i, char) in enumerated() {
            if char.isUppercase && i > 0 {
                result += " "
            }
            result += i == 0 ? char.uppercased() : String(char)
        }
        return result
    }
}
