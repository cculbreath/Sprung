//
//  DebriefView.swift
//  Sprung
//
//  Post-event debrief view for capturing contacts and insights.
//  Records new contacts made, notes, and follow-up actions.
//

import SwiftUI

struct DebriefView: View {
    let event: NetworkingEventOpportunity
    let coordinator: SearchOpsCoordinator

    @Environment(\.dismiss) private var dismiss

    @State private var overallNotes = ""
    @State private var newContacts: [NewContactEntry] = []
    @State private var keyInsights = ""
    @State private var followUpActions = ""
    @State private var rating: Int = 3
    @State private var wouldRecommend = true
    @State private var isSaving = false
    @State private var isGeneratingOutcomes = false
    @State private var generatedOutcomes: DebriefOutcomesResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                Divider()

                // Rating
                ratingSection

                Divider()

                // New Contacts
                contactsSection

                Divider()

                // Key Insights
                insightsSection

                Divider()

                // Follow-up Actions
                followUpSection

                Divider()

                // Notes
                notesSection

                Divider()

                // AI-Generated Outcomes
                outcomesSection

                // Submit
                submitSection
            }
            .padding()
        }
        .navigationTitle("Event Debrief")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debrief: \(event.name)")
                .font(.title)
                .fontWeight(.bold)

            HStack {
                Text(event.date, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(event.location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Rating

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW WAS IT?")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= rating ? .yellow : .gray)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Toggle("Would recommend", isOn: $wouldRecommend)
                    .toggleStyle(.checkbox)
            }

            Text(ratingDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var ratingDescription: String {
        switch rating {
        case 1: return "Not worth the time"
        case 2: return "Below expectations"
        case 3: return "Met expectations"
        case 4: return "Good networking opportunity"
        case 5: return "Excellent - highly valuable!"
        default: return ""
        }
    }

    // MARK: - Contacts Section

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEW CONTACTS")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    addNewContact()
                } label: {
                    Label("Add Contact", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
            }

            if newContacts.isEmpty {
                Text("No contacts added yet. Tap 'Add Contact' to record people you met.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
            } else {
                ForEach($newContacts) { $contact in
                    NewContactCard(contact: $contact, onDelete: {
                        newContacts.removeAll { $0.id == contact.id }
                    })
                }
            }
        }
    }

    private func addNewContact() {
        let entry = NewContactEntry()
        newContacts.append(entry)
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KEY INSIGHTS")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $keyInsights)
                .frame(minHeight: 80, maxHeight: 120)
                .font(.body)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)

            Text("What did you learn? Industry trends, company info, job opportunities?")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Follow-up Section

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FOLLOW-UP ACTIONS")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $followUpActions)
                .frame(minHeight: 80, maxHeight: 120)
                .font(.body)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)

            Text("What do you need to do next? Send connection requests, emails, research companies?")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADDITIONAL NOTES")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $overallNotes)
                .frame(minHeight: 100, maxHeight: 150)
                .font(.body)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
        }
    }

    // MARK: - Outcomes Section

    private var outcomesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI-SUGGESTED OUTCOMES")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await generateOutcomes() }
                } label: {
                    if isGeneratingOutcomes {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingOutcomes || (keyInsights.isEmpty && newContacts.isEmpty && overallNotes.isEmpty))
            }

            if let outcomes = generatedOutcomes {
                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(outcomes.summary)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }

                // Key Takeaways
                if !outcomes.keyTakeaways.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key Takeaways")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(outcomes.keyTakeaways, id: \.self) { takeaway in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                Text(takeaway)
                                    .font(.callout)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }

                // Follow-up Actions
                if !outcomes.followUpActions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Follow-up Actions")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(outcomes.followUpActions, id: \.contactName) { action in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: priorityIcon(action.priority))
                                    .foregroundStyle(priorityColor(action.priority))
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.contactName)
                                        .fontWeight(.medium)
                                    Text(action.action)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Text(action.deadline)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }

                // Opportunities
                if !outcomes.opportunitiesIdentified.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Opportunities Identified")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(outcomes.opportunitiesIdentified, id: \.self) { opportunity in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(opportunity)
                                    .font(.callout)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }

                // Next Steps
                if !outcomes.nextSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recommended Next Steps")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(Array(outcomes.nextSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.accentColor)
                                Text(step)
                                    .font(.callout)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
            } else {
                Text("Add some notes or contacts above, then tap 'Generate' to get AI-suggested follow-ups and next steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
            }
        }
    }

    private func priorityIcon(_ priority: String) -> String {
        switch priority.lowercased() {
        case "high": return "exclamationmark.circle.fill"
        case "medium": return "arrow.right.circle.fill"
        case "low": return "minus.circle.fill"
        default: return "circle.fill"
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .gray
        default: return .secondary
        }
    }

    // MARK: - Submit Section

    private var submitSection: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                Task { await submitDebrief() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Complete Debrief", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top)
    }

    // MARK: - Actions

    private func submitDebrief() async {
        isSaving = true
        defer { isSaving = false }

        // Update event with debrief info
        event.status = .debriefed
        event.eventNotes = overallNotes
        event.eventRating = EventRating(rawValue: rating)
        coordinator.eventStore.update(event)

        // Create contacts from entries
        for entry in newContacts where !entry.name.isEmpty {
            let contact = NetworkingContact(
                name: entry.name,
                company: entry.company.isEmpty ? nil : entry.company
            )
            contact.title = entry.title.isEmpty ? nil : entry.title
            contact.email = entry.email.isEmpty ? nil : entry.email
            contact.linkedInUrl = entry.linkedIn.isEmpty ? nil : entry.linkedIn
            contact.notes = entry.notes
            contact.metAt = event.name
            contact.metAtEventId = event.id
            contact.lastContactAt = Date()
            contact.warmth = ContactWarmth.hot // Just met them!

            coordinator.contactStore.add(contact)

            // Create follow-up task if they want to follow up
            if entry.wantsFollowUp {
                let followUpDate = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
                let interaction = NetworkingInteraction(
                    contactId: contact.id,
                    type: .email  // Use email as the follow-up type
                )
                interaction.followUpDate = followUpDate
                interaction.followUpAction = "Send follow-up message after meeting at \(event.name)"
                coordinator.interactionStore.add(interaction)
            }
        }

        // Update weekly goals
        coordinator.weeklyGoalStore.incrementEventsAttended()
        coordinator.weeklyGoalStore.incrementNewContacts(count: newContacts.filter { !$0.name.isEmpty }.count)

        Logger.info("Completed debrief for \(event.name) with \(newContacts.count) new contacts", category: .ai)

        dismiss()
    }

    private func generateOutcomes() async {
        isGeneratingOutcomes = true
        defer { isGeneratingOutcomes = false }

        let contactNames = newContacts.filter { !$0.name.isEmpty }.map { entry in
            var description = entry.name
            if !entry.company.isEmpty {
                description += " (\(entry.company))"
            }
            if !entry.notes.isEmpty {
                description += " - \(entry.notes)"
            }
            return description
        }

        do {
            generatedOutcomes = try await coordinator.generateDebriefOutcomes(
                event: event,
                keyInsights: keyInsights,
                contactsMade: contactNames,
                notes: overallNotes
            )
        } catch {
            Logger.error("Failed to generate debrief outcomes: \(error)", category: .ai)
        }
    }
}

// MARK: - New Contact Entry

struct NewContactEntry: Identifiable {
    let id = UUID()
    var name = ""
    var company = ""
    var title = ""
    var email = ""
    var linkedIn = ""
    var notes = ""
    var wantsFollowUp = true

    var firstName: String {
        let parts = name.split(separator: " ")
        return parts.first.map(String.init) ?? name
    }

    var lastName: String? {
        let parts = name.split(separator: " ")
        guard parts.count > 1 else { return nil }
        return parts.dropFirst().joined(separator: " ")
    }
}

struct NewContactCard: View {
    @Binding var contact: NewContactEntry
    let onDelete: () -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse
            HStack {
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if contact.name.isEmpty {
                    Text("New Contact")
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                } else {
                    Text(contact.name)
                        .fontWeight(.medium)
                    if !contact.company.isEmpty {
                        Text("@ \(contact.company)")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("Name", text: $contact.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Company", text: $contact.company)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 10) {
                        TextField("Title/Role", text: $contact.title)
                            .textFieldStyle(.roundedBorder)
                        TextField("Email", text: $contact.email)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("LinkedIn URL", text: $contact.linkedIn)
                        .textFieldStyle(.roundedBorder)

                    TextField("Notes (how you met, conversation topics)", text: $contact.notes)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Schedule follow-up in 2 days", isOn: $contact.wantsFollowUp)
                        .toggleStyle(.checkbox)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}
