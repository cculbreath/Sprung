import AppKit
import SwiftUI

struct ExperienceSectionViewCallbacks {
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
}

struct ExperienceCard<Content: View>: View {
    let onDelete: () -> Void
    var onToggleEdit: (() -> Void)? = nil
    var isEditing: Bool = false
    let content: Content
    @State private var isHovered = false

    init(onDelete: @escaping () -> Void, onToggleEdit: (() -> Void)? = nil, isEditing: Bool = false, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.onToggleEdit = onToggleEdit
        self.isEditing = isEditing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isHovered ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: 6) {
                    if let onToggleEdit {
                        Button(action: onToggleEdit) {
                            Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel(isEditing ? "Finish Editing" : "Edit Entry")
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Delete Entry")
                }
                .padding(8)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct ExperienceSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ExperienceAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}

struct ExperienceFieldRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            content
        }
    }
}

struct ExperienceTextField: View {
    let title: String
    @Binding var text: String
    var onChange: () -> Void

    init(_ title: String, text: Binding<String>, onChange: @escaping () -> Void) {
        self.title = title
        _text = text
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .onChange(of: text) { _, _ in onChange() }
    }
}

struct ExperienceTextEditor: View {
    let title: String
    @Binding var text: String
    var onChange: () -> Void

    init(_ title: String, text: Binding<String>, onChange: @escaping () -> Void) {
        self.title = title
        _text = text
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 100)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .onChange(of: text) { _, _ in onChange() }
    }
}

@ViewBuilder
func sectionContainer<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 16) {
        ExperienceSectionHeader(title, subtitle: subtitle)
        VStack(alignment: .leading, spacing: 16, content: content)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

func summarySubtitle(primary: String?, secondary: String?) -> String? {
    let first = primary?.trimmed()
    let second = secondary?.trimmed()
    let parts = [first, second].compactMap { value -> String? in
        guard let value, value.isEmpty == false else { return nil }
        return value
    }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

func dateRangeDescription(_ start: String, _ end: String) -> String? {
    let startTrim = start.trimmed()
    let endTrim = end.trimmed()
    switch (startTrim.isEmpty, endTrim.isEmpty) {
    case (true, true):
        return nil
    case (false, true):
        return "\(startTrim) – Present"
    case (true, false):
        return endTrim
    case (false, false):
        return "\(startTrim) – \(endTrim)"
    }
}
