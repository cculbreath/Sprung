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

    @State private var hasUnsavedChanges = false
    @State private var showDiscardAlert = false

    @FocusState private var focusedField: Field?

    private var isNewCard: Bool { card == nil }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !narrative.trimmingCharacters(in: .whitespaces).isEmpty
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
                    settingsSection
                }
                .padding(24)
            }

            Divider()

            // Footer with actions
            footerSection
        }
        .frame(width: 600, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(ChangeTracker(
            title: title, narrative: narrative, cardType: cardType,
            organization: organization, dateRange: dateRange, location: location,
            enabledByDefault: enabledByDefault, domains: domains,
            scaleItems: scaleItems, keywords: keywords,
            technologies: technologies, outcomes: outcomes,
            suggestedBullets: suggestedBullets,
            hasUnsavedChanges: $hasUnsavedChanges
        ))
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

            editableTagGroup("Technologies", systemImage: "cpu", items: $technologies, placeholder: "e.g., Kubernetes")
            editableListGroup("Outcomes", systemImage: "target", items: $outcomes, placeholder: "e.g., Reduced deploy time by 60%")
            editableListGroup("Suggested Bullets", systemImage: "list.bullet", items: $suggestedBullets, placeholder: "Resume bullet template")
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

// MARK: - Change Tracker

/// Breaks up the long onChange chain into a separate ViewModifier
/// so the Swift type-checker doesn't time out on the main body.
private struct ChangeTracker: ViewModifier {
    let title: String
    let narrative: String
    let cardType: KnowledgeCard.CardType?
    let organization: String
    let dateRange: String
    let location: String
    let enabledByDefault: Bool
    let domains: [String]
    let scaleItems: [String]
    let keywords: [String]
    let technologies: [String]
    let outcomes: [String]
    let suggestedBullets: [String]
    @Binding var hasUnsavedChanges: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: title) { _, _ in hasUnsavedChanges = true }
            .onChange(of: narrative) { _, _ in hasUnsavedChanges = true }
            .onChange(of: cardType) { _, _ in hasUnsavedChanges = true }
            .onChange(of: organization) { _, _ in hasUnsavedChanges = true }
            .onChange(of: dateRange) { _, _ in hasUnsavedChanges = true }
            .onChange(of: location) { _, _ in hasUnsavedChanges = true }
            .onChange(of: enabledByDefault) { _, _ in hasUnsavedChanges = true }
            .onChange(of: domains) { _, _ in hasUnsavedChanges = true }
            .onChange(of: scaleItems) { _, _ in hasUnsavedChanges = true }
            .onChange(of: keywords) { _, _ in hasUnsavedChanges = true }
            .onChange(of: technologies) { _, _ in hasUnsavedChanges = true }
            .onChange(of: outcomes) { _, _ in hasUnsavedChanges = true }
            .onChange(of: suggestedBullets) { _, _ in hasUnsavedChanges = true }
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
