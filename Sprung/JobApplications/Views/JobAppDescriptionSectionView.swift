//
//  JobAppDescriptionSectionView.swift
//  Sprung
//
//
import Foundation
import SwiftData
import SwiftUI

struct JobAppDescriptionSection: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var buttons: SaveButtons
    @AppStorage("useMarkdownForJobDescription") private var useMarkdownForJobDescription: Bool = true

    // State for skill highlighting
    @State private var hoveredSkill: JobSkillEvidence?
    @State private var selectedSkill: JobSkillEvidence?
    @State private var isEditingSkills: Bool = false

    private var activeSkill: JobSkillEvidence? {
        hoveredSkill ?? selectedSkill
    }

    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            @Bindable var boundSelApp = selApp

            HStack(alignment: .top, spacing: 12) {
                // Left column: Job Description
                descriptionColumn(boundSelApp: boundSelApp)
                    .frame(minWidth: 300)

                // Right column: Skills Panel (only if preprocessing complete)
                if let requirements = selApp.extractedRequirements,
                   !requirements.skillEvidence.isEmpty {
                    skillsColumn(requirements: requirements)
                        .frame(width: 280)
                }
            }
        } else {
            Text("No job application selected.")
                .padding()
        }
    }

    @ViewBuilder
    private func skillsColumn(requirements: ExtractedRequirements) -> some View {
        GroupBox(label: skillsHeader().padding(.top).padding(.bottom, 6)) {
            JobAppSkillsPanel(
                skillEvidence: requirements.skillEvidence,
                skillRecommendations: requirements.skillRecommendations,
                hoveredSkill: $hoveredSkill,
                selectedSkill: $selectedSkill,
                isEditing: $isEditingSkills
            )
        }
    }

    @ViewBuilder
    private func skillsHeader() -> some View {
        HStack {
            Text("Referenced Skills")
            Spacer()
            Button {
                isEditingSkills.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                    Text("Edit")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func descriptionColumn(boundSelApp: JobApp) -> some View {
        Section {
            if buttons.edit {
                // Bind to form when editing so saveForm() works correctly
                TextField("", text: Binding(
                    get: { jobAppStore.form.jobDescription },
                    set: { jobAppStore.form.jobDescription = $0 }
                ), axis: .vertical)
                    .lineLimit(15 ... 20)
                    .padding(.all, 3)
            } else if useMarkdownForJobDescription {
                ScrollView {
                    if boundSelApp.jobDescription.isEmpty {
                        Text("none listed")
                            .italic()
                            .foregroundColor(.secondary)
                            .padding(.all, 3)
                    } else {
                        RichTextView(
                            text: boundSelApp.jobDescription,
                            jobId: boundSelApp.id,
                            activeSkill: activeSkill
                        )
                        .textSelection(.enabled)
                        .padding(.all, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("\(boundSelApp.id)-\(activeSkill?.skillName ?? "")")
                    }
                }
            } else {
                Text(boundSelApp.jobDescription.isEmpty ? "none listed" : boundSelApp.jobDescription)
                    .textSelection(.enabled)
                    .padding(.all, 3)
                    .foregroundColor(.secondary)
                    .italic(boundSelApp.jobDescription.isEmpty)
            }
        }
        .insetGroupedStyle(header: getHeader())
    }

    @ViewBuilder
    private func getHeader() -> some View {
        if buttons.edit {
            markdownToggleHeader()
        } else {
            HStack {
                Text("Job Description")
                Spacer()
                Button {
                    buttons.edit = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                        Text("Edit")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func markdownToggleHeader() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Job Description")
                .font(.headline)
            HStack {
                Text("Format with rich text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("Format with rich text", isOn: $useMarkdownForJobDescription)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
                    .help("Toggle rich text formatting for job descriptions (bold headings, bulleted lists, links)")
            }
        }
    }
}

// MARK: - Rich Text View with Highlighting

struct RichTextView: View {
    let text: String
    let jobId: UUID
    var activeSkill: JobSkillEvidence?

    @State private var paragraphs: [JobDescriptionMarkdownParser.Paragraph] = []
    @State private var highlightScale: CGFloat = 1.0
    @State private var highlightOpacity: Double = 1.0

    private var highlightSpans: [TextSpan] {
        activeSkill?.evidenceSpans ?? []
    }

    private var highlightColor: Color {
        guard let skill = activeSkill else { return .green }
        switch skill.category {
        case .matched:
            return .green
        case .recommended:
            return .orange
        case .unmatched:
            return Color(.systemGray)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paragraphs) { paragraph in
                switch paragraph.type {
                case .normal:
                    normalParagraph(paragraph.content, startIndex: paragraph.startIndex)
                case .bold:
                    Text(paragraph.content)
                        .bold()
                        .foregroundColor(.primary)
                case .list:
                    bulletList(paragraph.content, startIndex: paragraph.startIndex)
                case let .listItem(itemText):
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                            .padding(.trailing, 4)
                        normalParagraph(itemText, startIndex: paragraph.startIndex)
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .onAppear {
            processParagraphs()
        }
        .onChange(of: jobId) { _, _ in
            paragraphs = []
            processParagraphs()
        }
        .onChange(of: activeSkill?.skillName) { oldValue, newValue in
            // Animate highlight appearance with bounce (similar to Cmd+F)
            if newValue != nil && oldValue != newValue {
                // Reset and animate
                highlightScale = 1.3
                highlightOpacity = 0.5
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0)) {
                    highlightScale = 1.0
                    highlightOpacity = 1.0
                }
            }
        }
    }

    private func normalParagraph(_ content: String, startIndex: Int) -> some View {
        let processedContent = processBoldInlineText(content, startIndex: startIndex)
        return processedContent
    }

    private func processBoldInlineText(_ content: String, startIndex: Int) -> some View {
        let segments = JobDescriptionMarkdownParser.boldSegments(in: content, startIndex: startIndex)

        // No bold runs (or the parse produced nothing) → render as plain highlighted text.
        if segments.isEmpty {
            return Text(processTextWithHighlights(content, startIndex: startIndex))
                .foregroundColor(.primary)
        }

        var attributedString = AttributedString()
        for segment in segments {
            var part = processTextWithHighlights(segment.text, startIndex: segment.offset)
            if segment.isBold {
                part.font = Font.body.bold()
            }
            attributedString.append(part)
        }
        return Text(attributedString)
            .foregroundColor(.primary)
    }

    private func bulletList(_ content: String, startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(content.split(separator: "\n").enumerated()), id: \.offset) { index, line in
                let lineText = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if lineText.hasPrefix("* ") || lineText.hasPrefix("• ") {
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                        let itemText = lineText.dropFirst(lineText.hasPrefix("* ") ? 2 : 2)
                        normalParagraph(String(itemText), startIndex: startIndex + index * 10) // Approximate
                    }
                    .padding(.leading, 4)
                } else if !lineText.isEmpty {
                    normalParagraph(lineText, startIndex: startIndex + index * 10)
                }
            }
        }
    }

    private func processTextWithHighlights(_ content: String, startIndex: Int) -> AttributedString {
        var attributedText = processEmailLinks(content)

        // Apply highlights for matching spans - use category-specific color
        for span in highlightSpans {
            // Check if this span overlaps with current content
            let contentEnd = startIndex + content.count
            if span.start < contentEnd && span.end > startIndex {
                // Find the text to highlight within this content (case-insensitive search)
                if let range = attributedText.range(of: span.text, options: .caseInsensitive) {
                    // Use category-matched highlight color with white text
                    attributedText[range].backgroundColor = highlightColor
                    attributedText[range].foregroundColor = .white
                }
            }
        }

        return attributedText
    }

    private func processParagraphs() {
        paragraphs = JobDescriptionMarkdownParser.paragraphs(from: text)
    }

    private func processEmailLinks(_ content: String) -> AttributedString {
        do {
            var attributedText = AttributedString(content)
            let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
            let emailRegex = try NSRegularExpression(pattern: emailPattern)
            let nsString = content as NSString
            let matches = emailRegex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let emailRange = match.range
                let email = nsString.substring(with: emailRange)
                if let range = attributedText.range(of: email) {
                    attributedText[range].link = URL(string: "mailto:\(email)")
                    attributedText[range].foregroundColor = .blue
                }
            }
            return attributedText
        } catch {
            return AttributedString(content)
        }
    }
}
