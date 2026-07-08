//
//  AIStatusIcon.swift
//  Sprung
//
//  Icon-based AI status indicator. Every attribute/collection shows
//  an always-colored icon indicating its AI review mode.
//

import AppKit
import SwiftUI

/// Icon modes for AI status display.
/// Single editability axis: a node is either marked editable, inheriting
/// editability from an editable ancestor (included), explicitly excluded from
/// that group, or unset.
enum AIIconMode: Equatable {
    case editable   // target, teal - Node itself marked for AI revision (.aiToReplace)
    case included   // film.stack, teal - Inside an editable group (inherited)
    case excluded   // custom.bundled.member.disabled, gray - Opted out of an editable group
    case unset      // sparkles, gray (primary) - Not part of any AI revision

    var symbolName: String {
        switch self {
        case .editable: return "target"
        case .included: return "film.stack"
        case .excluded: return "custom.bundled.member.disabled"
        case .unset: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .editable, .included: return .teal
        case .excluded: return .secondary
        case .unset: return .primary
        }
    }

    var usesHierarchical: Bool {
        switch self {
        case .included: return true
        default: return false
        }
    }

    /// Whether this is a custom symbol from the asset catalog (not SF Symbols)
    var isCustomSymbol: Bool {
        switch self {
        case .excluded: return true
        default: return false
        }
    }

    var helpText: String {
        switch self {
        case .editable: return "Marked for AI revision"
        case .included: return "Included in AI revision (inherited from section)"
        case .excluded: return "Excluded from AI revision"
        case .unset: return "Click to include in AI revision"
        }
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

// MARK: - Mode Detection

/// Determines the appropriate AIIconMode for a tree node, derived solely from
/// the node's editability status and its inheritance from editable ancestors.
struct AIIconModeResolver {

    /// The editability mode for a node:
    /// - `.editable`  : node itself is `.aiToReplace`
    /// - `.excluded`  : node opted out of an editable group (`.excludedFromGroup`)
    /// - `.included`  : node sits under an editable ancestor (inherited)
    /// - `.unset`     : node is not part of any AI revision
    static func detectSingleMode(for node: TreeNode) -> AIIconMode {
        if node.status == .aiToReplace {
            return .editable
        }
        if node.status == .excludedFromGroup {
            return .excluded
        }
        if node.isInheritedAISelection {
            return .included
        }
        return .unset
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
