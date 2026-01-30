//
//  AIStatusIcon.swift
//  Sprung
//
//  Icon-based AI status indicator. Every attribute/collection shows
//  an always-colored icon indicating its AI review mode.
//

import AppKit
import SwiftUI

/// Icon modes for AI status display
enum AIIconMode: Equatable {
    case iteratedCollection      // film.stack, indigo - Collection with [] iterate
    case iteratedMember          // inset.filled.bottomhalf.rectangle, indigo (hierarchical)
    case bundledCollection       // circle.hexagongrid.circle, purple - Collection with .* bundle
    case bundledMember           // custom.bundled.member, purple - Child in bundled collection
    case excludedBundledMember   // custom.bundled.member.disabled, gray - Excluded from bundle review
    case excludedIteratedMember  // custom.iterated.member.disabled, gray - Excluded from iterate review
    case unset                   // sparkles, gray (primary) - No AI assignment
    case solo                    // target, teal - Individual node marked for AI

    var symbolName: String {
        switch self {
        case .iteratedCollection: return "film.stack"
        case .iteratedMember: return "inset.filled.bottomhalf.rectangle"
        case .bundledCollection: return "circle.hexagongrid.circle"
        case .bundledMember: return "custom.bundled.member"
        case .excludedBundledMember: return "custom.bundled.member.disabled"
        case .excludedIteratedMember: return "custom.iterated.member.disabled"
        case .unset: return "sparkles"
        case .solo: return "target"
        }
    }

    var color: Color {
        switch self {
        case .iteratedCollection, .iteratedMember: return .indigo
        case .bundledCollection, .bundledMember: return .purple
        case .excludedBundledMember, .excludedIteratedMember: return .secondary
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
        switch self {
        case .bundledMember, .excludedBundledMember, .excludedIteratedMember: return true
        default: return false
        }
    }

    var helpText: String {
        switch self {
        case .iteratedCollection: return "Iterate: N reviews (one per entry)"
        case .iteratedMember: return "Included in iterate review (per entry)"
        case .bundledCollection: return "Bundle: All entries combined into 1 review"
        case .bundledMember: return "Included in bundle review (all combined)"
        case .excludedBundledMember: return "Excluded from bundle review"
        case .excludedIteratedMember: return "Excluded from iterate review"
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
            Image(mode.symbolName)
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
    var size: CGFloat = 14
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AIIconImage(mode: mode, size: size)
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

// MARK: - AI Icon Menu Button

/// A button that shows the AI icon with correct colors and displays a popover menu on click.
/// The menuContent closure receives a dismiss action to close the popover after selection.
/// Set `showDropIndicator` to show a small ▼ hint next to the icon.
struct AIIconMenuButton<MenuContent: View>: View {
    let mode: AIIconMode
    let size: CGFloat
    let showDropIndicator: Bool
    @ViewBuilder let menuContent: (@escaping () -> Void) -> MenuContent

    @State private var showingMenu = false

    init(mode: AIIconMode, size: CGFloat = 14, showDropIndicator: Bool = false, @ViewBuilder menuContent: @escaping (@escaping () -> Void) -> MenuContent) {
        self.mode = mode
        self.size = size
        self.showDropIndicator = showDropIndicator
        self.menuContent = menuContent
    }

    var body: some View {
        Button {
            showingMenu = true
        } label: {
            HStack(spacing: 1) {
                AIIconImage(mode: mode, size: size)
                if showDropIndicator {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.helpText)
        .popover(isPresented: $showingMenu, arrowEdge: .bottom) {
            popoverMenuContainer {
                menuContent { showingMenu = false }
            }
        }
    }
}

/// Standard popover menu container with tight corner radius and consistent sizing.
private struct popoverMenuContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.vertical, 6)
        .frame(minWidth: 200)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Popover Menu Items

/// A menu item button for use inside AIIconMenuButton popovers.
/// Layout: [checkmark] [text] [spacer] [optional chevron]
/// Checkmarks on left, submenu chevrons on right. No inline icons.
struct PopoverMenuItem: View {
    let title: String
    let isChecked: Bool
    let showChevron: Bool
    let isDestructive: Bool
    let action: () -> Void

    init(
        _ title: String,
        isChecked: Bool = false,
        showChevron: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isChecked = isChecked
        self.showChevron = showChevron
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Left: checkmark (always reserve space for alignment)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .opacity(isChecked ? 1 : 0)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isDestructive ? .red : .primary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Native Menu Support (AppKit)

/// NSMenuItem subclass with closure-based action handling.
final class ActionMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    convenience init(_ title: String, checked: Bool = false, action handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(performAction), keyEquivalent: "")
        self.handler = handler
        self.target = self
        self.state = checked ? .on : .off
    }

    @objc private func performAction() {
        handler?()
    }
}

/// Invisible NSView anchor for positioning native menus from SwiftUI.
/// Place as `.background()` on a Button to anchor native menus.
final class NativeMenuAnchor {
    weak var view: NSView?

    func showMenu(_ menu: NSMenu) {
        guard let view = view else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
    }
}

struct NativeMenuAnchorView: NSViewRepresentable {
    let anchor: NativeMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        anchor.view = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// Button with colored AI icon that opens a native NSMenu on click.
/// Use for collection-level menus that need fly-out submenus.
struct AIIconNativeMenuButton: View {
    let mode: AIIconMode
    let showDropIndicator: Bool
    let menuBuilder: () -> NSMenu

    @State private var anchor = NativeMenuAnchor()

    init(mode: AIIconMode, showDropIndicator: Bool = false, menuBuilder: @escaping () -> NSMenu) {
        self.mode = mode
        self.showDropIndicator = showDropIndicator
        self.menuBuilder = menuBuilder
    }

    var body: some View {
        Button {
            anchor.showMenu(menuBuilder())
        } label: {
            HStack(spacing: 1) {
                AIIconImage(mode: mode)
                if showDropIndicator {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.helpText)
        .background(NativeMenuAnchorView(anchor: anchor))
    }
}

/// Button with resolved AI icon(s) that opens a native NSMenu on click.
/// For dual-icon patterns (member→collection with arrow).
struct ResolvedAIIconNativeMenuButton: View {
    let resolution: AIIconResolution
    let showDropIndicator: Bool
    let menuBuilder: () -> NSMenu

    @State private var anchor = NativeMenuAnchor()

    init(resolution: AIIconResolution, showDropIndicator: Bool = false, menuBuilder: @escaping () -> NSMenu) {
        self.resolution = resolution
        self.showDropIndicator = showDropIndicator
        self.menuBuilder = menuBuilder
    }

    var body: some View {
        Button {
            anchor.showMenu(menuBuilder())
        } label: {
            HStack(spacing: 1) {
                ResolvedAIIcon(resolution: resolution)
                if showDropIndicator {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(resolution.primary.helpText)
        .background(NativeMenuAnchorView(anchor: anchor))
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
    /// Returns excluded variant if node has `.excludedFromGroup` status.
    private static func resolveLeafMemberMode(for node: TreeNode) -> AIIconMode? {
        guard let parent = node.parent else { return nil }
        let isExcluded = node.status == .excludedFromGroup

        // Case 1: Scalar array child (parent has bundledAttributes["*"] or enumeratedAttributes["*"])
        if parent.bundledAttributes?.contains("*") == true {
            return isExcluded ? .excludedBundledMember : .bundledMember
        }
        if parent.enumeratedAttributes?.contains("*") == true {
            return isExcluded ? .excludedIteratedMember : .iteratedMember
        }

        // Case 2: Scalar attribute under a collection entry
        // e.g., "name" field under skill entry where skills section has bundledAttributes["name"]
        // node.parent = entry, node.parent.parent = section (collection)
        if node.orderedChildren.isEmpty, let collection = parent.parent {
            let nodeName = node.name.isEmpty ? node.displayLabel : node.name

            if collection.bundledAttributes?.contains(nodeName) == true {
                return isExcluded ? .excludedBundledMember : .bundledMember
            }
            if collection.enumeratedAttributes?.contains(nodeName) == true {
                return isExcluded ? .excludedIteratedMember : .iteratedMember
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
                return isExcluded ? .excludedIteratedMember : .iteratedMember
            }

            // Without suffix → children are bundled
            if collection.enumeratedAttributes?.contains(parentName) == true ||
               collection.bundledAttributes?.contains(parentName) == true {
                return isExcluded ? .excludedBundledMember : .bundledMember
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
