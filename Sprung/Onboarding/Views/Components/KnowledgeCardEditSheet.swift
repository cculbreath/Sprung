import SwiftUI

/// Full editing sheet for knowledge cards.
/// Supports editing all fields including title, content, metadata, and card type.
struct KnowledgeCardEditSheet: View {
    let card: KnowledgeCard?
    let onSave: (KnowledgeCard) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var narrative: String = ""
    @State private var cardType: CardType = .employment
    @State private var organization: String = ""
    @State private var dateRange: String = ""
    @State private var location: String = ""
    @State private var enabledByDefault: Bool = true

    // Extractable metadata
    @State private var domains: [String] = []
    @State private var scaleItems: [String] = []
    @State private var keywords: [String] = []

    // Enrichment fields
    @State private var technologies: [String] = []
    @State private var outcomes: [String] = []
    @State private var suggestedBullets: [String] = []
    @State private var evidenceQuality: String = ""

    // Facts
    @State private var facts: [KnowledgeCardFact] = []

    // Verbatim excerpts
    @State private var verbatimExcerpts: [VerbatimExcerpt] = []

    // Evidence anchors
    @State private var evidenceAnchors: [EvidenceAnchor] = []

    @State private var showDiscardAlert = false

    @FocusState private var focusedField: Field?

    private var isNewCard: Bool { card == nil }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !narrative.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        guard let card else {
            return !title.isEmpty || !narrative.isEmpty || !organization.isEmpty
        }
        return title != card.title
            || narrative != card.narrative
            || cardType != card.cardType
            || organization != (card.organization ?? "")
            || dateRange != (card.dateRange ?? "")
            || location != (card.location ?? "")
            || enabledByDefault != card.enabledByDefault
            || domains != card.extractable.domains
            || scaleItems != card.extractable.scale
            || keywords != card.extractable.keywords
            || technologies != card.technologies
            || outcomes != card.outcomes
            || suggestedBullets != card.suggestedBullets
            || evidenceQuality != (card.evidenceQuality ?? "")
            || facts.count != card.facts.count
            || verbatimExcerpts.count != card.verbatimExcerpts.count
            || evidenceAnchors.count != card.evidenceAnchors.count
    }

    private var wordCount: Int {
        narrative.split(separator: " ").count
    }

    enum Field {
        case title, narrative, organization, dateRange, location
    }

    init(card: KnowledgeCard?, onSave: @escaping (KnowledgeCard) -> Void, onCancel: @escaping () -> Void) {
        self.card = card
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize state from card if editing
        if let card = card {
            _title = State(initialValue: card.title)
            _narrative = State(initialValue: card.narrative)
            _cardType = State(initialValue: card.cardType ?? .employment)
            _organization = State(initialValue: card.organization ?? "")
            _dateRange = State(initialValue: card.dateRange ?? "")
            _location = State(initialValue: card.location ?? "")
            _enabledByDefault = State(initialValue: card.enabledByDefault)

            // Extractable metadata
            _domains = State(initialValue: card.extractable.domains)
            _scaleItems = State(initialValue: card.extractable.scale)
            _keywords = State(initialValue: card.extractable.keywords)

            // Enrichment fields
            _technologies = State(initialValue: card.technologies)
            _outcomes = State(initialValue: card.outcomes)
            _suggestedBullets = State(initialValue: card.suggestedBullets)
            _evidenceQuality = State(initialValue: card.evidenceQuality ?? "")

            // Facts, verbatim excerpts, evidence anchors
            _facts = State(initialValue: card.facts)
            _verbatimExcerpts = State(initialValue: card.verbatimExcerpts)
            _evidenceAnchors = State(initialValue: card.evidenceAnchors)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    basicInfoSection
                    metadataSection
                    contentSection
                    extractableSection
                    enrichmentSection
                    if !facts.isEmpty || !isNewCard { factsSection }
                    if !verbatimExcerpts.isEmpty || !isNewCard { verbatimExcerptsSection }
                    if !evidenceAnchors.isEmpty || !isNewCard { evidenceAnchorsSection }
                    settingsSection
                }
                .padding(24)
            }

            Divider()

            // Footer with actions
            footerSection
        }
        .frame(width: 600, height: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                onCancel()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .onKeyPress(.escape) {
            handleCancel()
            return .handled
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isNewCard ? "New Knowledge Card" : "Edit Knowledge Card")
                    .font(.title2.weight(.semibold))
                if !isNewCard {
                    Text("Created \(card?.isFromOnboarding == true ? "during onboarding" : "manually")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Close button
            Button(action: handleCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Information")
                .font(.headline)
                .foregroundStyle(.primary)

            // Card Type
            VStack(alignment: .leading, spacing: 6) {
                Text("Card Type")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Type", selection: $cardType) {
                    Label("Employment", systemImage: "briefcase.fill").tag(CardType.employment)
                    Label("Project", systemImage: "folder.fill").tag(CardType.project)
                    Label("Achievement", systemImage: "trophy.fill").tag(CardType.achievement)
                    Label("Education", systemImage: "graduationcap.fill").tag(CardType.education)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Title/Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("e.g., Senior Software Engineer at Acme Corp", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                // Organization
                VStack(alignment: .leading, spacing: 6) {
                    Label("Organization", systemImage: "building.2")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("Company or institution", text: $organization)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .organization)
                }

                // Location
                VStack(alignment: .leading, spacing: 6) {
                    Label("Location", systemImage: "location")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("City, State or Remote", text: $location)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .location)
                }
            }

            // Time Period
            VStack(alignment: .leading, spacing: 6) {
                Label("Time Period", systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("e.g., 2020-01 to 2024-06, or 2020-Present", text: $dateRange)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .dateRange)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Content")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                // Word count indicator
                HStack(spacing: 4) {
                    let color: Color = wordCount < 100 ? .orange : (wordCount >= 500 ? .green : .primary)
                    Image(systemName: "doc.text")
                        .foregroundStyle(color)
                    Text("\(wordCount) words")
                        .foregroundStyle(color)
                }
                .font(.caption)
            }

            TextEditor(text: $narrative)
                .font(.body)
                .frame(minHeight: 200, maxHeight: 300)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .focused($focusedField, equals: .narrative)

            if wordCount < 100 {
                Text("Tip: More detailed content helps generate better resumes. Aim for 500+ words.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var extractableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Job Matching")
                .font(.headline)
                .foregroundStyle(.primary)

            editableTagGroup("Domains", systemImage: "globe", items: $domains, placeholder: "e.g., Backend Engineering")
            editableTagGroup("Keywords", systemImage: "tag", items: $keywords, placeholder: "e.g., distributed systems")
            editableTagGroup("Scale & Metrics", systemImage: "chart.bar", items: $scaleItems, placeholder: "e.g., 10M daily active users")
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var enrichmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enrichment Data")
                .font(.headline)
                .foregroundStyle(.primary)

            // Evidence quality picker
            VStack(alignment: .leading, spacing: 6) {
                Label("Evidence Quality", systemImage: "shield.checkered")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Evidence Quality", selection: $evidenceQuality) {
                    Text("None").tag("")
                    Text("Strong").tag("strong")
                    Text("Moderate").tag("moderate")
                    Text("Weak").tag("weak")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            editableTagGroup("Technologies", systemImage: "cpu", items: $technologies, placeholder: "e.g., Kubernetes")
            editableListGroup("Outcomes", systemImage: "target", items: $outcomes, placeholder: "e.g., Reduced deploy time by 60%")
            editableListGroup("Suggested Bullets", systemImage: "list.bullet", items: $suggestedBullets, placeholder: "Resume bullet template")
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Facts Section

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Facts")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.category.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(fact.statement)
                            .font(.caption)
                            .lineLimit(3)
                        if let confidence = fact.confidence, !confidence.isEmpty {
                            Text("Confidence: \(confidence)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        facts.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            AddFactField { category, statement in
                facts.append(KnowledgeCardFact(
                    category: category,
                    statement: statement,
                    confidence: nil,
                    source: nil
                ))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Verbatim Excerpts Section

    private var verbatimExcerptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verbatim Excerpts")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(Array(verbatimExcerpts.enumerated()), id: \.offset) { index, excerpt in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(excerpt.context)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(excerpt.text)
                            .font(.caption)
                            .lineLimit(4)
                        HStack(spacing: 8) {
                            Text(excerpt.location)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(excerpt.preservationReason)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        verbatimExcerpts.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Evidence Anchors Section

    private var evidenceAnchorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evidence Anchors")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(Array(evidenceAnchors.enumerated()), id: \.offset) { index, anchor in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(anchor.documentId)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(anchor.location)
                            .font(.caption)
                        if let excerpt = anchor.verbatimExcerpt, !excerpt.isEmpty {
                            Text(excerpt)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        evidenceAnchors.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Reusable Tag/List Editors

    private func editableTagGroup(_ label: String, systemImage: String, items: Binding<[String]>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if !items.wrappedValue.isEmpty {
                FlowStack(spacing: 6, verticalSpacing: 6) {
                    ForEach(Array(items.wrappedValue.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 4) {
                            Text(item)
                                .font(.caption)
                            Button {
                                items.wrappedValue.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                    }
                }
            }

            AddItemField(placeholder: placeholder) { newItem in
                items.wrappedValue.append(newItem)
            }
        }
    }

    private func editableListGroup(_ label: String, systemImage: String, items: Binding<[String]>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(Array(items.wrappedValue.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text(item)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                    Button {
                        items.wrappedValue.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            AddItemField(placeholder: placeholder) { newItem in
                items.wrappedValue.append(newItem)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .foregroundStyle(.primary)

            Toggle(isOn: $enabledByDefault) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enabled by Default")
                        .font(.subheadline.weight(.medium))
                    Text("Include this card when generating new resumes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var footerSection: some View {
        HStack {
            // Validation status
            if !isValid {
                Label(
                    title.trimmingCharacters(in: .whitespaces).isEmpty ? "Title required" : "Content required",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Spacer()

            Button("Cancel", action: handleCancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

            Button(isNewCard ? "Create Card" : "Save Changes", action: saveCard)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(20)
    }

    private func handleCancel() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            onCancel()
        }
    }

    private func saveCard() {
        guard isValid else { return }

        if let existingCard = card {
            // Update existing card
            existingCard.title = title.trimmingCharacters(in: .whitespaces)
            existingCard.narrative = narrative.trimmingCharacters(in: .whitespaces)
            existingCard.cardType = cardType
            existingCard.organization = organization.isEmpty ? nil : organization.trimmingCharacters(in: .whitespaces)
            existingCard.dateRange = dateRange.isEmpty ? nil : dateRange.trimmingCharacters(in: .whitespaces)
            existingCard.location = location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces)
            existingCard.enabledByDefault = enabledByDefault
            existingCard.extractable = ExtractableMetadata(domains: domains, scale: scaleItems, keywords: keywords)
            existingCard.technologies = technologies
            existingCard.outcomes = outcomes
            existingCard.suggestedBullets = suggestedBullets
            existingCard.evidenceQuality = evidenceQuality.isEmpty ? nil : evidenceQuality
            existingCard.facts = facts
            existingCard.verbatimExcerpts = verbatimExcerpts
            existingCard.evidenceAnchors = evidenceAnchors
            onSave(existingCard)
        } else {
            // Create new card
            let newCard = KnowledgeCard(
                title: title.trimmingCharacters(in: .whitespaces),
                narrative: narrative.trimmingCharacters(in: .whitespaces),
                cardType: cardType,
                dateRange: dateRange.isEmpty ? nil : dateRange.trimmingCharacters(in: .whitespaces),
                organization: organization.isEmpty ? nil : organization.trimmingCharacters(in: .whitespaces),
                location: location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces),
                extractable: ExtractableMetadata(domains: domains, scale: scaleItems, keywords: keywords),
                enabledByDefault: enabledByDefault,
                isFromOnboarding: false
            )
            newCard.technologies = technologies
            newCard.outcomes = outcomes
            newCard.suggestedBullets = suggestedBullets
            onSave(newCard)
        }
    }
}

// MARK: - Add Item Field

private struct AddItemField: View {
    let placeholder: String
    let onAdd: (String) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { addItem() }

            Button(action: addItem) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addItem() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        text = ""
    }
}

// MARK: - Add Fact Field

private struct AddFactField: View {
    let onAdd: (String, String) -> Void

    @State private var category = ""
    @State private var statement = ""

    private var canAdd: Bool {
        !category.trimmingCharacters(in: .whitespaces).isEmpty
            && !statement.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("Category", text: $category)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(maxWidth: 120)

            TextField("Statement", text: $statement)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { addFact() }

            Button(action: addFact) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
    }

    private func addFact() {
        guard canAdd else { return }
        onAdd(
            category.trimmingCharacters(in: .whitespaces),
            statement.trimmingCharacters(in: .whitespaces)
        )
        category = ""
        statement = ""
    }
}
