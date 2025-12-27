//
//  EventPrepView.swift
//  Sprung
//
//  Event preparation view for networking events.
//  Shows event details, research, elevator pitch, and goals.
//

import SwiftUI

struct EventPrepView: View {
    let event: NetworkingEventOpportunity
    let coordinator: DiscoveryCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var isGeneratingPitch = false
    @State private var isGeneratingGoals = false
    @State private var pitchText: String = ""
    @State private var goalText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Event Header
                eventHeaderSection

                Divider()

                // Event Details
                eventDetailsSection

                Divider()

                // Elevator Pitch
                elevatorPitchSection

                Divider()

                // Goals
                goalsSection

                Divider()

                // Contacts to Reconnect
                if !potentialContacts.isEmpty {
                    contactsSection
                }

                // Action Buttons
                actionButtonsSection
            }
            .padding()
        }
        .navigationTitle("Event Prep")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add to Calendar") {
                    addToCalendar()
                }
                .disabled(event.calendarEventId != nil)
            }
        }
        .onAppear {
            pitchText = event.pitchScript ?? ""
            goalText = event.goal ?? ""
        }
    }

    // MARK: - Event Header

    private var eventHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: event.eventType.icon)
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text(event.name)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(event.eventType.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let recommendation = event.llmRecommendation {
                    RecommendationBadge(recommendation: recommendation)
                }
            }

            if let description = event.eventDescription {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Event Details

    private var eventDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVENT DETAILS")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Date and Time
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(event.date, style: .date)
                            .fontWeight(.medium)
                        if let time = event.time {
                            Text(time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                }

                Spacer()

                // Days until event
                if let daysUntil = daysUntilEvent {
                    Text(daysUntil == 0 ? "Today!" : "\(daysUntil) days away")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(daysUntil == 0 ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .cornerRadius(8)
                }
            }

            // Location
            Label {
                VStack(alignment: .leading) {
                    Text(event.location)
                        .fontWeight(.medium)
                    if let address = event.locationAddress, address != event.location {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if event.isVirtual, let link = event.virtualLink {
                        Link(link, destination: URL(string: link) ?? URL(string: "https://example.com")!)
                            .font(.caption)
                    }
                }
            } icon: {
                Image(systemName: event.isVirtual ? "video" : "location")
                    .foregroundStyle(.orange)
            }

            // Organizer
            if let organizer = event.organizer {
                Label(organizer, systemImage: "person.circle")
                    .foregroundStyle(.secondary)
            }

            // Cost
            if let cost = event.cost {
                Label(cost, systemImage: "dollarsign.circle")
                    .foregroundStyle(.secondary)
            }

            // URL
            if let urlStr = URL(string: event.url) {
                Link(destination: urlStr) {
                    Label("Event Page", systemImage: "link")
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Elevator Pitch

    private var elevatorPitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ELEVATOR PITCH")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await generatePitch() }
                } label: {
                    if isGeneratingPitch {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingPitch)
            }

            TextEditor(text: $pitchText)
                .frame(minHeight: 100, maxHeight: 150)
                .font(.body)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)

            Text("Practice your 30-second introduction tailored to this event.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if pitchText != (event.pitchScript ?? "") {
                Button("Save Pitch") {
                    savePitch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR GOALS")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await generateGoals() }
                } label: {
                    if isGeneratingGoals {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Suggest", systemImage: "lightbulb")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingGoals)
            }

            TextEditor(text: $goalText)
                .frame(minHeight: 80, maxHeight: 120)
                .font(.body)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)

            Text("What do you want to achieve at this event?")
                .font(.caption)
                .foregroundStyle(.secondary)

            if goalText != (event.goal ?? "") {
                Button("Save Goal") {
                    saveGoal()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Contacts Section

    private var potentialContacts: [NetworkingContact] {
        coordinator.contactStore.allContacts.filter { contact in
            // Find contacts who might be at this event
            contact.warmth != .dormant && (
                contact.isAtTargetCompany ||
                contact.relationshipHealth == .healthy ||
                contact.relationshipHealth == .needsAttention
            )
        }.prefix(5).map { $0 }
    }

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTACTS TO LOOK FOR")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(potentialContacts) { contact in
                HStack {
                    Image(systemName: contact.relationshipHealth.icon)
                        .foregroundStyle(healthColor(contact.relationshipHealth))

                    VStack(alignment: .leading) {
                        Text(contact.displayName)
                            .fontWeight(.medium)
                        if let company = contact.company {
                            Text(company)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(contact.warmth.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(warmthColor(contact.warmth).opacity(0.2))
                        .cornerRadius(4)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            HStack {
                if event.status == .planned {
                    Button {
                        markAsAttended()
                    } label: {
                        Label("I Attended This Event", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button {
                        markAsPlanned()
                    } label: {
                        Label("Mark as Planned", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(event.status == .planned)
                }

                Button {
                    skipEvent()
                } label: {
                    Label("Skip Event", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(event.status == .skipped)

                Button(role: .destructive) {
                    deleteEvent()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer()

                if let urlStr = URL(string: event.url) {
                    Link(destination: urlStr) {
                        Label("Open Event Page", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Show debrief prompt for attended events
            if event.attended && event.status != .debriefed {
                NavigationLink {
                    DebriefView(event: event, coordinator: coordinator)
                } label: {
                    Label("Complete Debrief", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    // MARK: - Computed Properties

    private var daysUntilEvent: Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: event.date)
        return calendar.dateComponents([.day], from: today, to: eventDay).day
    }

    // MARK: - Actions

    private func generatePitch() async {
        isGeneratingPitch = true
        defer { isGeneratingPitch = false }

        do {
            if let generated = try await coordinator.generateEventPitch(for: event) {
                pitchText = generated
            }
        } catch {
            Logger.error("Failed to generate pitch: \(error)", category: .ai)
        }
    }

    private func generateGoals() async {
        isGeneratingGoals = true
        defer { isGeneratingGoals = false }

        // Use a reasonable default goal suggestion
        goalText = """
        1. Meet 3-5 new contacts in my target industry
        2. Get at least 2 business cards/LinkedIn connections
        3. Learn about current trends in the field
        4. Practice my elevator pitch
        """
    }

    private func savePitch() {
        event.pitchScript = pitchText
        coordinator.eventStore.update(event)
    }

    private func saveGoal() {
        event.goal = goalText
        coordinator.eventStore.update(event)
    }

    private func markAsPlanned() {
        event.status = .planned
        coordinator.eventStore.update(event)
    }

    private func markAsAttended() {
        event.status = .attended
        event.attended = true
        event.attendedAt = Date()
        coordinator.eventStore.update(event)
    }

    private func skipEvent() {
        event.status = .skipped
        coordinator.eventStore.update(event)
    }

    private func deleteEvent() {
        coordinator.eventStore.delete(event)
        dismiss()
    }

    private func addToCalendar() {
        Task {
            do {
                let eventId = try await coordinator.calendarService?.createCalendarEvent(for: event)
                if let eventId = eventId {
                    event.calendarEventId = eventId
                    coordinator.eventStore.update(event)
                }
            } catch {
                Logger.error("Failed to add to calendar: \(error)", category: .ai)
            }
        }
    }

    // MARK: - Helpers

    private func healthColor(_ health: RelationshipHealth) -> Color {
        switch health {
        case .healthy: return .green
        case .needsAttention: return .yellow
        case .decaying: return .orange
        case .dormant: return .gray
        case .new: return .blue
        }
    }

    private func warmthColor(_ warmth: ContactWarmth) -> Color {
        switch warmth {
        case .hot: return .red
        case .warm: return .orange
        case .cold: return .blue
        case .dormant: return .gray
        }
    }
}

// MARK: - Supporting Views

struct RecommendationBadge: View {
    let recommendation: AttendanceRecommendation

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: recommendation.icon)
            Text(recommendation.rawValue)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .cornerRadius(8)
    }

    private var backgroundColor: Color {
        switch recommendation {
        case .strongYes: return .green
        case .yes: return .teal
        case .maybe: return .yellow
        case .skip: return .gray
        }
    }
}

