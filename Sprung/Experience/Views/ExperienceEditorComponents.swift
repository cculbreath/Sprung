import AppKit
import SwiftUI
import UniformTypeIdentifiers
struct ExperienceSectionViewCallbacks {
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
}
struct ExperienceCard<Content: View>: View {
    let onDelete: () -> Void
    var onToggleEdit: (() -> Void)?
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
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(8)
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
    VStack(alignment: .leading, spacing: 12) {
        ExperienceSectionHeader(title, subtitle: subtitle)
        VStack(alignment: .leading, spacing: 8, content: content)
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
struct GenericExperienceSectionView<Item, Editor: View, Summary: View>: View where Item: Identifiable & Equatable, Item.ID == UUID {
    @Binding var items: [Item]
    let metadata: ExperienceSectionMetadata
    let callbacks: ExperienceSectionViewCallbacks
    let newItem: () -> Item
    let title: (Item) -> String
    let subtitle: (Item) -> String?
    let editorBuilder: (Binding<Item>, ExperienceSectionViewCallbacks) -> Editor
    let summaryBuilder: (Item) -> Summary
    @State private var draggingID: UUID?
    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: { delete(entryID) },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: title(entry),
                        subtitle: subtitle(entry)
                    )
                    if editing {
                        editorBuilder(item, callbacks)
                    } else {
                        summaryBuilder(entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }
            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }
            ExperienceAddButton(title: metadata.addButtonTitle) {
                addNewItem()
            }
        }
    }
    private func delete(_ id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            callbacks.endEditing(id)
            items.remove(at: index)
            callbacks.onChange()
        }
    }
    private func addNewItem() {
        let entry = newItem()
        let entryID = entry.id
        items.append(entry)
        callbacks.beginEditing(entryID)
        callbacks.onChange()
    }
}
struct ExperienceSectionTrailingDropArea<Item: Identifiable & Equatable>: View where Item.ID == UUID {
    @Binding var items: [Item]
    @Binding var draggingID: UUID?
    var onChange: () -> Void
    var body: some View {
        Color.clear
            .frame(height: 10)
            .contentShape(Rectangle())
            .onDrop(
                of: [.plainText],
                delegate: ExperienceReorderTrailingDropDelegate(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            )
    }
}
struct ExperienceFieldDescriptor<Model> {
    enum Control {
        case textField
        case textEditor
    }
    let label: String
    let keyPath: WritableKeyPath<Model, String>
    let control: Control
    static func textField(_ label: String, _ keyPath: WritableKeyPath<Model, String>) -> ExperienceFieldDescriptor<Model> {
        ExperienceFieldDescriptor(label: label, keyPath: keyPath, control: .textField)
    }
    static func textEditor(_ label: String, _ keyPath: WritableKeyPath<Model, String>) -> ExperienceFieldDescriptor<Model> {
        ExperienceFieldDescriptor(label: label, keyPath: keyPath, control: .textEditor)
    }
}
enum ExperienceFieldLayout<Model> {
    case row([ExperienceFieldDescriptor<Model>])
    case block(ExperienceFieldDescriptor<Model>)
}
struct ExperienceFieldFactory<Model>: View {
    let layout: [ExperienceFieldLayout<Model>]
    @Binding var model: Model
    let onChange: () -> Void
    var body: some View {
        ForEach(Array(layout.enumerated()), id: \.offset) { _, layout in
            switch layout {
            case .row(let descriptors):
                ExperienceFieldRow {
                    ForEach(Array(descriptors.enumerated()), id: \.offset) { _, descriptor in
                        fieldView(descriptor)
                    }
                }
            case .block(let descriptor):
                fieldView(descriptor)
            }
        }
    }
    @ViewBuilder
    private func fieldView(_ descriptor: ExperienceFieldDescriptor<Model>) -> some View {
        let binding = Binding(
            get: { model[keyPath: descriptor.keyPath] },
            set: { model[keyPath: descriptor.keyPath] = $0 }
        )
        switch descriptor.control {
        case .textField:
            ExperienceTextField(descriptor.label, text: binding, onChange: onChange)
        case .textEditor:
            ExperienceTextEditor(descriptor.label, text: binding, onChange: onChange)
        }
    }
}
struct SummaryFieldDescriptor<Model> {
    let render: (Model) -> AnyView
    static func row(label: String, keyPath: KeyPath<Model, String>) -> SummaryFieldDescriptor<Model> {
        SummaryFieldDescriptor { entry in
            AnyView(SummaryRow(label: label, value: entry[keyPath: keyPath]))
        }
    }
    static func optionalRow(label: String, value: @escaping (Model) -> String?) -> SummaryFieldDescriptor<Model> {
        SummaryFieldDescriptor { entry in
            let renderedValue = value(entry) ?? ""
            return AnyView(SummaryRow(label: label, value: renderedValue))
        }
    }
    static func textBlock(label: String, keyPath: KeyPath<Model, String>) -> SummaryFieldDescriptor<Model> {
        SummaryFieldDescriptor { entry in
            AnyView(SummaryTextBlock(label: label, value: entry[keyPath: keyPath]))
        }
    }
    static func bulletList(label: String? = nil, values: @escaping (Model) -> [String]) -> SummaryFieldDescriptor<Model> {
        SummaryFieldDescriptor { entry in
            AnyView(SummaryBulletList(label: label, items: values(entry)))
        }
    }
    static func chipGroup(label: String, values: @escaping (Model) -> [String]) -> SummaryFieldDescriptor<Model> {
        SummaryFieldDescriptor { entry in
            AnyView(SummaryChipGroup(label: label, values: values(entry)))
        }
    }
}
struct SummarySectionFactory<Model>: View {
    let entry: Model
    let descriptors: [SummaryFieldDescriptor<Model>]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(descriptors.enumerated()), id: \.offset) { _, descriptor in
                descriptor.render(entry)
            }
        }
        .padding(.top, 4)
    }
}
