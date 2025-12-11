import AppKit
import SwiftUI
struct SingleLineHighlightListEditor: View {
    @Binding var items: [HighlightDraft]
    var onChange: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlights")
                .font(.headline)
            ForEach(items) { item in
                let itemID = item.id
                ExperienceCard(onDelete: {
                    items.removeAll { $0.id == itemID }
                    onChange()
                }, content: {
                    ExperienceFieldRow {
                        if let index = items.firstIndex(where: { $0.id == itemID }) {
                            ExperienceTextField("Highlight", text: $items[index].text, onChange: onChange)
                        }
                    }
                })
            }
            Button("Add Highlight") {
                items.append(HighlightDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}
struct VolunteerHighlightListEditor: View {
    @Binding var items: [VolunteerHighlightDraft]
    var onChange: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlights")
                .font(.headline)
            ForEach(items) { item in
                let itemID = item.id
                ExperienceCard(onDelete: {
                    items.removeAll { $0.id == itemID }
                    onChange()
                }, content: {
                    if let index = items.firstIndex(where: { $0.id == itemID }) {
                        ExperienceTextEditor("Highlight", text: $items[index].text, onChange: onChange)
                    }
                })
            }
            Button("Add Highlight") {
                items.append(VolunteerHighlightDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}
struct ProjectHighlightListEditor: View {
    @Binding var items: [ProjectHighlightDraft]
    var onChange: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlights")
                .font(.headline)
            ForEach(items) { item in
                let itemID = item.id
                ExperienceCard(onDelete: {
                    items.removeAll { $0.id == itemID }
                    onChange()
                }, content: {
                    if let index = items.firstIndex(where: { $0.id == itemID }) {
                        ExperienceTextEditor("Highlight", text: $items[index].text, onChange: onChange)
                    }
                })
            }
            Button("Add Highlight") {
                items.append(ProjectHighlightDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}
struct CourseListEditor: View {
    @Binding var items: [CourseDraft]
    var onChange: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Courses")
                .font(.headline)
            ForEach(items) { item in
                let itemID = item.id
                ExperienceCard(onDelete: {
                    items.removeAll { $0.id == itemID }
                    onChange()
                }, content: {
                    if let index = items.firstIndex(where: { $0.id == itemID }) {
                        ExperienceTextField("Course", text: $items[index].name, onChange: onChange)
                    }
                })
            }
            Button("Add Course") {
                items.append(CourseDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}
struct KeywordChipsEditor: View {
    let title: String
    @Binding var keywords: [KeywordDraft]
    var onChange: () -> Void
    @Environment(CareerKeywordStore.self) private var keywordStore: CareerKeywordStore
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    private var normalizedExisting: Set<String> {
        Set(keywords.map { $0.keyword.lowercased() })
    }
    private var suggestions: [String] {
        keywordStore.suggestions(matching: inputText, excluding: normalizedExisting)
    }
    private let chipGridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: chipGridColumns, alignment: .leading, spacing: 8) {
                ForEach(keywords) { keyword in
                    KeywordChip(keyword: keyword.keyword) {
                        removeKeyword(keyword)
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Add keyword", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isInputFocused)
                        .onSubmit(commitPendingKeyword)
                        .onChange(of: inputText) { _, newValue in
                            handleDelimitedInput(newValue)
                        }
                        .onChange(of: isInputFocused) { _, isFocused in
                            handleFocusChange(isFocused)
                        }
                    if suggestions.isEmpty == false {
                        SuggestionList(
                            suggestions: suggestions,
                            onSelect: { suggestion in
                                addKeyword(suggestion)
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
    private func handleDelimitedInput(_ newValue: String) {
        guard newValue.contains(",") else { return }
        let parts = newValue.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return }
        for part in parts.dropLast() {
            addKeyword(String(part))
        }
        let trailing = parts.last.map(String.init) ?? ""
        let trimmedTrailing = trailing.trimmed()
        inputText = trailing.hasSuffix(" ") ? trimmedTrailing + " " : trimmedTrailing
    }
    private func handleFocusChange(_ isFocused: Bool) {
        guard isFocused == false else { return }
        let pending = inputText.trimmed()
        guard pending.isEmpty == false else { return }
        addKeyword(pending, shouldRefocus: false)
    }
    private func commitPendingKeyword() {
        addKeyword(inputText)
    }
    private func addKeyword(_ rawValue: String, shouldRefocus: Bool = true) {
        let trimmed = rawValue.trimmed()
        guard trimmed.isEmpty == false else {
            inputText = ""
            if shouldRefocus { isInputFocused = true }
            return
        }
        guard normalizedExisting.contains(trimmed.lowercased()) == false else {
            inputText = ""
            if shouldRefocus { isInputFocused = true }
            return
        }
        var newKeyword = KeywordDraft()
        newKeyword.keyword = trimmed
        keywords.append(newKeyword)
        keywordStore.registerKeyword(trimmed)
        inputText = ""
        if shouldRefocus {
            isInputFocused = true
        }
        onChange()
    }
    private func removeKeyword(_ keyword: KeywordDraft) {
        if let index = keywords.firstIndex(where: { $0.id == keyword.id }) {
            keywords.remove(at: index)
            onChange()
        }
    }
}
struct KeywordChip: View {
    let keyword: String
    var onRemove: (() -> Void)?
    @State private var isHovered = false
    var body: some View {
        HStack(spacing: 6) {
            Text(keyword)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if isHovered, let onRemove {
                Button(action: onRemove, label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                })
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .accessibilityLabel("Remove \(keyword)")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isHovered && onRemove != nil ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isHovered && onRemove != nil ? 1.5 : 1)
        )
        .onHover { hovering in
            guard onRemove != nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
struct SuggestionList: View {
    let suggestions: [String]
    var onSelect: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: { onSelect(suggestion) }, label: {
                        HStack {
                            Text(suggestion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                        }
                    })
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    if suggestion != suggestions.last {
                        Divider()
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.top, 2)
        .frame(maxWidth: 320, maxHeight: 180)
    }
}
struct RoleListEditor: View {
    let title: String
    @Binding var items: [RoleDraft]
    var onChange: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(items) { item in
                let itemID = item.id
                ExperienceCard(onDelete: {
                    items.removeAll { $0.id == itemID }
                    onChange()
                }, content: {
                    if let index = items.firstIndex(where: { $0.id == itemID }) {
                        ExperienceTextField("Role", text: $items[index].role, onChange: onChange)
                    }
                })
            }
            Button("Add Role") {
                items.append(RoleDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}
