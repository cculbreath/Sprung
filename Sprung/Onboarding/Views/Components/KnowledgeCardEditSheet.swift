import SwiftUI

/// Full editing sheet for knowledge cards.
/// Supports editing all fields including title, content, metadata, and card type.
struct KnowledgeCardEditSheet: View {
    let card: ResRef?
    let onSave: (ResRef) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var cardType: String = "job"
    @State private var organization: String = ""
    @State private var timePeriod: String = ""
    @State private var location: String = ""
    @State private var enabledByDefault: Bool = true

    @State private var hasUnsavedChanges = false
    @State private var showDiscardAlert = false

    @FocusState private var focusedField: Field?

    private var isNewCard: Bool { card == nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var wordCount: Int {
        content.split(separator: " ").count
    }

    enum Field {
        case name, content, organization, timePeriod, location
    }

    init(card: ResRef?, onSave: @escaping (ResRef) -> Void, onCancel: @escaping () -> Void) {
        self.card = card
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize state from card if editing
        if let card = card {
            _name = State(initialValue: card.name)
            _content = State(initialValue: card.content)
            _cardType = State(initialValue: card.cardType ?? "job")
            _organization = State(initialValue: card.organization ?? "")
            _timePeriod = State(initialValue: card.timePeriod ?? "")
            _location = State(initialValue: card.location ?? "")
            _enabledByDefault = State(initialValue: card.enabledByDefault)
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
        .onChange(of: name) { _, _ in hasUnsavedChanges = true }
        .onChange(of: content) { _, _ in hasUnsavedChanges = true }
        .onChange(of: cardType) { _, _ in hasUnsavedChanges = true }
        .onChange(of: organization) { _, _ in hasUnsavedChanges = true }
        .onChange(of: timePeriod) { _, _ in hasUnsavedChanges = true }
        .onChange(of: location) { _, _ in hasUnsavedChanges = true }
        .onChange(of: enabledByDefault) { _, _ in hasUnsavedChanges = true }
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
                    Label("Job", systemImage: "briefcase.fill").tag("job")
                    Label("Skill", systemImage: "star.fill").tag("skill")
                    Label("Education", systemImage: "graduationcap.fill").tag("education")
                    Label("Project", systemImage: "folder.fill").tag("project")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Title/Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("e.g., Senior Software Engineer at Acme Corp", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
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

                TextField("e.g., 2020-01 to 2024-06, or 2020-Present", text: $timePeriod)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .timePeriod)
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

            TextEditor(text: $content)
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
                .focused($focusedField, equals: .content)

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
                    name.trimmingCharacters(in: .whitespaces).isEmpty ? "Title required" : "Content required",
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
            existingCard.name = name.trimmingCharacters(in: .whitespaces)
            existingCard.content = content.trimmingCharacters(in: .whitespaces)
            existingCard.cardType = cardType
            existingCard.organization = organization.isEmpty ? nil : organization.trimmingCharacters(in: .whitespaces)
            existingCard.timePeriod = timePeriod.isEmpty ? nil : timePeriod.trimmingCharacters(in: .whitespaces)
            existingCard.location = location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces)
            existingCard.enabledByDefault = enabledByDefault
            onSave(existingCard)
        } else {
            // Create new card
            let newCard = ResRef(
                name: name.trimmingCharacters(in: .whitespaces),
                content: content.trimmingCharacters(in: .whitespaces),
                enabledByDefault: enabledByDefault,
                cardType: cardType,
                timePeriod: timePeriod.isEmpty ? nil : timePeriod.trimmingCharacters(in: .whitespaces),
                organization: organization.isEmpty ? nil : organization.trimmingCharacters(in: .whitespaces),
                location: location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces),
                sourcesJSON: nil,
                isFromOnboarding: false
            )
            onSave(newCard)
        }
    }
}
