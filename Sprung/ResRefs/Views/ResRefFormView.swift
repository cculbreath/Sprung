//
//  ResRefFormView.swift
//  Sprung
//
//  Form view for creating and editing knowledge cards.
//  Supports both legacy content-based cards and fact-based cards.
//

import SwiftUI
import UniformTypeIdentifiers

struct ResRefFormView: View {
    @State private var isTargeted: Bool = false
    @State var sourceName: String = ""
    @State var sourceContent: String = ""
    @State var enabledByDefault: Bool = true

    // Fact-based card fields
    @State private var cardType: String = ""
    @State private var timePeriod: String = ""
    @State private var organization: String = ""
    @State private var location: String = ""
    @State private var technologies: [String] = []
    @State private var suggestedBullets: [String] = []
    @State private var newTechnology: String = ""
    @State private var newBullet: String = ""
    @State private var expandedFacts: Set<String> = []

    @State private var dropErrorMessage: String?
    @Binding var isSheetPresented: Bool
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore: KnowledgeCardStore

    var existingCard: KnowledgeCard?

    init(isSheetPresented: Binding<Bool>, existingCard: KnowledgeCard? = nil) {
        _isSheetPresented = isSheetPresented
        self.existingCard = existingCard
    }

    private var isFactBased: Bool {
        existingCard?.isFactBasedCard == true
    }

    var body: some View {
        @Bindable var knowledgeCardStore = knowledgeCardStore
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    basicInfoSection

                    if isFactBased {
                        metadataSection
                        technologiesSection
                        bulletsSection
                        factsSection
                    } else {
                        contentSection
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            footerSection
        }
        .frame(width: isFactBased ? 650 : 500, height: isFactBased ? 700 : 450)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            handleOnDrop(providers: providers)
        }
        .onAppear {
            loadExistingData()
        }
        .alert("Import Failed", isPresented: Binding(
            get: { dropErrorMessage != nil },
            set: { if !$0 { dropErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                dropErrorMessage = nil
            }
        } message: {
            Text(dropErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            if isFactBased, let card = existingCard {
                let typeInfo = card.cardTypeDisplay
                Image(systemName: typeInfo.icon)
                    .foregroundStyle(.secondary)
                Text(typeInfo.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text(existingCard == nil ? "Add Knowledge Card" : "Edit Knowledge Card")
                .font(.headline)

            Spacer()
        }
        .padding()
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Name:")
                    .frame(width: 100, alignment: .trailing)
                TextField("Card title", text: $sourceName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            HStack {
                Text("Enabled:")
                    .frame(width: 100, alignment: .trailing)
                Toggle("", isOn: $enabledByDefault)
                    .toggleStyle(SwitchToggleStyle())
                Spacer()
            }
        }
    }

    // MARK: - Metadata Section (Fact-Based)

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("Time Period:")
                    .frame(width: 100, alignment: .trailing)
                TextField("e.g., 2020-09 to 2024-06", text: $timePeriod)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            HStack {
                Text("Organization:")
                    .frame(width: 100, alignment: .trailing)
                TextField("Company, school, etc.", text: $organization)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            HStack {
                Text("Location:")
                    .frame(width: 100, alignment: .trailing)
                TextField("City, State or Remote", text: $location)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Technologies Section

    private var technologiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technologies")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Tags display
            TechTagFlowLayout(spacing: 6) {
                ForEach(technologies, id: \.self) { tech in
                    HStack(spacing: 4) {
                        Text(tech)
                            .font(.caption)
                        Button(action: { technologies.removeAll { $0 == tech } }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // Add new technology
            HStack {
                TextField("Add technology...", text: $newTechnology)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        addTechnology()
                    }
                Button("Add") {
                    addTechnology()
                }
                .buttonStyle(.bordered)
                .disabled(newTechnology.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func addTechnology() {
        let tech = newTechnology.trimmingCharacters(in: .whitespaces)
        if !tech.isEmpty && !technologies.contains(tech) {
            technologies.append(tech)
            newTechnology = ""
        }
    }

    // MARK: - Bullets Section

    private var bulletsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Resume Bullets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(suggestedBullets.count) bullets")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Bullets list
            ForEach(Array(suggestedBullets.enumerated()), id: \.offset) { index, bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(bullet)
                        .font(.callout)
                        .lineLimit(3)

                    Spacer()

                    Button(action: { suggestedBullets.remove(at: index) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)

                if index < suggestedBullets.count - 1 {
                    Divider()
                }
            }

            // Add new bullet
            HStack(alignment: .top) {
                TextField("Add bullet point...", text: $newBullet, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(2...4)

                Button("Add") {
                    addBullet()
                }
                .buttonStyle(.bordered)
                .disabled(newBullet.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func addBullet() {
        let bullet = newBullet.trimmingCharacters(in: .whitespaces)
        if !bullet.isEmpty {
            suggestedBullets.append(bullet)
            newBullet = ""
        }
    }

    // MARK: - Facts Section

    @ViewBuilder
    private var factsSection: some View {
        if let card = existingCard, !card.facts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Extracted Facts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(card.facts.count) facts")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Group by category
                ForEach(Array(card.factsByCategory.keys.sorted()), id: \.self) { category in
                    if let facts = card.factsByCategory[category] {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedFacts.contains(category) },
                                set: { if $0 { expandedFacts.insert(category) } else { expandedFacts.remove(category) } }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(facts) { fact in
                                    factRow(fact)
                                }
                            }
                            .padding(.leading, 8)
                        } label: {
                            HStack {
                                Image(systemName: categoryIcon(category))
                                    .foregroundStyle(categoryColor(category))
                                    .frame(width: 20)
                                Text(category.capitalized)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text("\(facts.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func factRow(_ fact: KnowledgeCardFact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.statement)
                .font(.callout)

            HStack(spacing: 8) {
                if let confidence = fact.confidence {
                    Text(confidence)
                        .font(.caption2)
                        .foregroundStyle(confidenceColor(confidence))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(confidenceColor(confidence).opacity(0.1))
                        .clipShape(Capsule())
                }

                if let source = fact.source, let quote = source.verbatimQuote {
                    Text("\"\(quote.prefix(50))...\"")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "responsibility": return "list.bullet.clipboard"
        case "achievement": return "trophy"
        case "technology": return "cpu"
        case "metric": return "chart.bar"
        case "scope": return "person.3"
        case "context": return "building.2"
        case "recognition": return "star"
        default: return "doc.text"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "responsibility": return .blue
        case "achievement": return .orange
        case "technology": return .purple
        case "metric": return .green
        case "scope": return .cyan
        case "context": return .gray
        case "recognition": return .yellow
        default: return .secondary
        }
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence.lowercased() {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .secondary
        }
    }

    // MARK: - Content Section (Legacy)

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content:")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            CustomTextEditor(sourceContent: $sourceContent)
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Cancel") {
                isSheetPresented = false
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Save") {
                if sourceName.trimmingCharacters(in: .whitespaces).isEmpty { return }
                saveRefForm()
                resetRefForm()
                closePopup()
            }
            .buttonStyle(.borderedProminent)
            .disabled(sourceName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadExistingData() {
        guard let card = existingCard else { return }

        sourceName = card.title
        sourceContent = card.narrative
        enabledByDefault = card.enabledByDefault

        // Load fact-based fields
        cardType = card.cardType?.rawValue ?? ""
        timePeriod = card.dateRange ?? ""
        organization = card.organization ?? ""
        location = card.location ?? ""
        technologies = card.technologies
        suggestedBullets = card.suggestedBullets
    }

    // MARK: - Save

    private func saveRefForm() {
        if let card = existingCard {
            // Update existing
            card.title = sourceName
            card.enabledByDefault = enabledByDefault

            if isFactBased {
                card.dateRange = timePeriod.isEmpty ? nil : timePeriod
                card.organization = organization.isEmpty ? nil : organization
                card.location = location.isEmpty ? nil : location
                card.technologies = technologies
                card.suggestedBullets = suggestedBullets
            } else {
                card.narrative = sourceContent
            }

            knowledgeCardStore.update(card)
        } else {
            // Create new (legacy format)
            let newCard = KnowledgeCard(
                title: sourceName,
                narrative: sourceContent,
                enabledByDefault: enabledByDefault
            )
            knowledgeCardStore.add(newCard)
        }
    }

    private func resetRefForm() {
        sourceName = ""
        sourceContent = ""
        enabledByDefault = true
        cardType = ""
        timePeriod = ""
        organization = ""
        location = ""
        technologies = []
        suggestedBullets = []
    }

    private func closePopup() {
        isSheetPresented = false
    }

    // MARK: - File Drop

    private func handleOnDrop(providers: [NSItemProvider]) -> Bool {
        guard !isFactBased else { return false } // Don't allow drops on fact-based cards

        var didRequestLoad = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didRequestLoad = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let urlData = item as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil)
                else {
                    Logger.error("Failed to resolve dropped file URL")
                    showDropError("Could not access the dropped file.")
                    return
                }
                guard isSupportedTextFile(url) else {
                    Logger.warning("Unsupported file type dropped: \(url.pathExtension)")
                    showDropError("Unsupported file type: \(url.pathExtension.uppercased()). Please drop a plain text, Markdown, or JSON file.")
                    return
                }
                Task.detached {
                    do {
                        let text = try String(contentsOf: url, encoding: .utf8)
                        let fileName = url.deletingPathExtension().lastPathComponent
                        await MainActor.run {
                            self.sourceName = fileName
                            self.sourceContent = text
                            self.dropErrorMessage = nil
                            saveRefForm()
                            resetRefForm()
                            closePopup()
                        }
                    } catch {
                        Logger.error("Failed to load dropped file as UTF-8 text: \(error.localizedDescription)")
                        await MainActor.run {
                            self.showDropError("Could not read the file using UTF-8 encoding.")
                        }
                    }
                }
            }
        }
        return didRequestLoad
    }

    private func isSupportedTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .plainText) ||
                type.conforms(to: .utf8PlainText) ||
                type.conforms(to: .utf16PlainText) ||
                type.conforms(to: .json) {
                return true
            }
            if let markdown = UTType(filenameExtension: "md"), type == markdown { return true }
            if let markdownLong = UTType(filenameExtension: "markdown"), type == markdownLong { return true }
        }
        let allowedExtensions: Set<String> = ["txt", "md", "markdown", "json", "csv", "yaml", "yml"]
        return allowedExtensions.contains(ext)
    }

    private func showDropError(_ message: String) {
        DispatchQueue.main.async {
            self.dropErrorMessage = message
        }
    }
}

// MARK: - Flow Layout for Tags

struct TechTagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
