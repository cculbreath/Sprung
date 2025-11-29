//
//  JobAppDescriptionSectionView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//
import Foundation
import SwiftData
import SwiftUI
struct JobAppDescriptionSection: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var buttons: SaveButtons
    @AppStorage("useMarkdownForJobDescription") private var useMarkdownForJobDescription: Bool = true
    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            @Bindable var boundSelApp = selApp
            Section {
                if buttons.edit {
                    TextField("", text: $boundSelApp.jobDescription, axis: .vertical)
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
                            // Reset the view with a new unique ID when the job description changes
                            RichTextView(text: boundSelApp.jobDescription, jobId: boundSelApp.id)
                                .textSelection(.enabled)
                                .padding(.all, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(boundSelApp.id) // Force view to refresh when selected job changes
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
        } else {
            // Handle the case where selectedApp is nil
            Text("No job application selected.")
                .padding()
        }
    }
    @ViewBuilder
    private func getHeader() -> some View {
        if buttons.edit {
            markdownToggleHeader()
        } else {
            Text("Job Description")
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
struct RichTextView: View {
    let text: String
    let jobId: UUID // Add jobId to track changes in selected job
    @State private var paragraphs: [Paragraph] = []
    struct Paragraph: Identifiable {
        let id = UUID()
        let content: String
        let type: ParagraphType
    }
    enum ParagraphType {
        case normal
        case bold
        case list
        case listItem(String)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paragraphs) { paragraph in
                switch paragraph.type {
                case .normal:
                    normalParagraph(paragraph.content)
                case .bold:
                    Text(paragraph.content)
                        .bold()
                        .foregroundColor(.primary)
                case .list:
                    bulletList(paragraph.content)
                case let .listItem(text):
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                            .padding(.trailing, 4)
                        normalParagraph(text)
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .onAppear {
            processParagraphs()
        }
        .onChange(of: jobId) { _, _ in
            // Reset paragraphs and reprocess when job changes
            paragraphs = []
            processParagraphs()
        }
    }
    private func normalParagraph(_ content: String) -> some View {
        let processedContent = processBoldInlineText(content)
        return processedContent
    }
    private func processBoldInlineText(_ content: String) -> some View {
        // Check for the simple case first - no bold text
        if !content.contains("**") {
            return Text(processEmailLinks(content))
                .foregroundColor(.primary)
        }
        // If we get here, we need to process bold text
        var segments: [TextSegment] = []
        let pattern = #"\*\*(.+?)\*\*|([^*]+)"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsText = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if match.numberOfRanges > 2 {
                    // Check which capture group matched
                    if match.range(at: 1).location != NSNotFound {
                        // Bold text (without **)
                        let boldText = nsText.substring(with: match.range(at: 1))
                        segments.append(TextSegment(text: boldText, isBold: true))
                    } else if match.range(at: 2).location != NSNotFound {
                        // Regular text
                        let regularText = nsText.substring(with: match.range(at: 2))
                        segments.append(TextSegment(text: regularText, isBold: false))
                    }
                } else {
                    // Fallback for the whole match
                    let wholeMatch = nsText.substring(with: match.range)
                    segments.append(TextSegment(text: wholeMatch, isBold: false))
                }
            }
        } catch {
            return Text(processEmailLinks(content))
                .foregroundColor(.primary)
        }
        if segments.isEmpty {
            // If no segments were created, return the original text
            return Text(processEmailLinks(content))
                .foregroundColor(.primary)
        }
        // Build the combined text using AttributedString for modern SwiftUI
        var attributedString = AttributedString()
        for segment in segments {
            var part = processEmailLinks(segment.text)
            if segment.isBold {
                part.font = Font.body.bold()
            }
            attributedString.append(part)
        }

        return Text(attributedString)
            .foregroundColor(.primary)
    }
    struct TextSegment {
        let text: String
        let isBold: Bool
    }
    private func bulletList(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(content.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                let lineText = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if lineText.hasPrefix("* ") || lineText.hasPrefix("• ") {
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                        let itemText = lineText.dropFirst(lineText.hasPrefix("* ") ? 2 : 2)
                        normalParagraph(String(itemText))
                    }
                    .padding(.leading, 4)
                } else if !lineText.isEmpty {
                    normalParagraph(lineText)
                }
            }
        }
    }
    private func processParagraphs() {
        var result: [Paragraph] = []
        // Preprocess the text to handle problematic patterns
        var preprocessedText = text
        // First, explicitly handle the problematic pattern where newlines are between content and closing asterisks
        // Special pattern matches: **The opportunity\n\n**
        let problemPattern1 = #"\*\*([^*\n]+)[\s\n]+\*\*"#
        if let regex = try? NSRegularExpression(pattern: problemPattern1, options: []) {
            let nsString = preprocessedText as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: preprocessedText, options: [], range: range)
            for match in matches.reversed() where match.numberOfRanges > 1 {
                let contentRange = match.range(at: 1)
                let content = nsString.substring(with: contentRange)
                let replacement = "**\(content)**"
                preprocessedText = (preprocessedText as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        // Second, handle sections that have newlines after the closing asterisks
        // Pattern like: "**Title**\n\n"
        preprocessedText = preprocessedText.replacingOccurrences(
            of: "\\*\\*([^*]+?)\\*\\*\\s*\\n\\s*\\n",
            with: "**$1**\n\n",
            options: .regularExpression
        )
        // Split by double newlines to get paragraphs
        let sections = preprocessedText.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for section in sections {
            // Check for bullet list
            if section.contains("\n* ") || section.contains("\n• ") || section.hasPrefix("* ") || section.hasPrefix("• ") {
                result.append(Paragraph(content: section, type: .list))
                continue
            }
            // Use regex to precisely detect "**Title**" patterns including whitespace and newlines
            let boldTitlePattern = #"^\*\*(.+?)\*\*[\s\n]*"#
            do {
                let regex = try NSRegularExpression(pattern: boldTitlePattern, options: [.dotMatchesLineSeparators])
                let nsSection = section as NSString
                let matches = regex.matches(in: section, options: [], range: NSRange(location: 0, length: nsSection.length))
                if !matches.isEmpty, let match = matches.first {
                    // Found a bold title pattern
                    if match.numberOfRanges > 1 {
                        // Extract the title text (without **)
                        let titleRange = match.range(at: 1)
                        let boldTitle = nsSection.substring(with: titleRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        // Add the bold title as a paragraph
                        result.append(Paragraph(content: boldTitle, type: .bold))
                        // Check if there's content after the bold title
                        if match.range.upperBound < nsSection.length {
                            let remainingText = nsSection.substring(from: match.range.upperBound).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !remainingText.isEmpty {
                                result.append(Paragraph(content: remainingText, type: .normal))
                            }
                        }
                    } else {
                        // Fallback for unexpected match structure
                        result.append(Paragraph(content: section, type: .normal))
                    }
                } else {
                    // No bold title match found - check for bold inline patterns
                    let clearedText = cleanAsterisks(section)
                    result.append(Paragraph(content: clearedText, type: .normal))
                }
            } catch {
                // Regex error - use the section as is
                result.append(Paragraph(content: section, type: .normal))
            }
        }
        paragraphs = result
    }
    // Helper to clean up any remaining asterisks in normal text
    private func cleanAsterisks(_ text: String) -> String {
        // Replace "**text**" patterns with "text"
        var result = text
        // Handle the case where "**text**" is at the start of a line
        let pattern = #"\*\*(.+?)\*\*"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            // Process matches from end to beginning to avoid index issues
            for match in matches.reversed() where match.numberOfRanges > 1 {
                let contentRange = match.range(at: 1)
                let content = nsText.substring(with: contentRange)
                let range = match.range
                result = (result as NSString).replacingCharacters(in: range, with: content)
            }
        } catch {
            Logger.debug("🧹 Failed to normalize markdown markers: \(error.localizedDescription)")
        }
        return result
    }
    private func processEmailLinks(_ content: String) -> AttributedString {
        do {
            // Create a basic attributed string
            var attributedText = AttributedString(content)
            // Regular expression for email addresses
            let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
            let emailRegex = try NSRegularExpression(pattern: emailPattern)
            // Find all matches
            let nsString = content as NSString
            let matches = emailRegex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
            // Apply links to each email match
            for match in matches {
                let emailRange = match.range
                let email = nsString.substring(with: emailRange)
                // Find the corresponding range in the AttributedString
                if let range = attributedText.range(of: email) {
                    // Add link attribute
                    attributedText[range].link = URL(string: "mailto:\(email)")
                    attributedText[range].foregroundColor = .blue
                }
            }
            return attributedText
        } catch {
            // Fallback if regex fails
            return AttributedString(content)
        }
    }
}
