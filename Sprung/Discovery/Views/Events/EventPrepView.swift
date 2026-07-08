//
//  EventPrepView.swift
//  Sprung
//
//  Event preparation view for networking events.
//  Shows event details, elevator pitch, goals, talking points,
//  target companies, conversation starters, and things to avoid.
//

import SwiftUI

struct EventPrepView: View {
    let event: NetworkingEventOpportunity
    let coordinator: DiscoveryCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var isGeneratingPrep = false
    @State private var pitchText: String = ""
    @State private var goalText: String = ""
    @State private var prepError: String?
    @State private var calendarError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Event Header
                eventHeaderSection

                Divider()

                // Event Details
                eventDetailsSection

                Divider()

                // AI Prep Generation
                prepGenerationSection

                Divider()

                // Elevator Pitch
                elevatorPitchSection

                Divider()

                // Goals
                goalsSection

                // AI Prep Results
                if let talkingPoints = event.talkingPoints, !talkingPoints.isEmpty {
                    Divider()
                    talkingPointsSection(talkingPoints)
                }

                if let targetCompanies = event.targetCompanies, !targetCompanies.isEmpty {
                    Divider()
                    targetCompaniesSection(targetCompanies)
                }

                if let starters = event.conversationStarters, !starters.isEmpty {
                    Divider()
                    conversationStartersSection(starters)
                }

                if let thingsToAvoid = event.thingsToAvoid, !thingsToAvoid.isEmpty {
                    Divider()
                    thingsToAvoidSection(thingsToAvoid)
                }

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
        .alert("Prep Generation Failed", isPresented: Binding(
            get: { prepError != nil },
            set: { if !$0 { prepError = nil } }
        )) {
            Button("OK") { prepError = nil }
        } message: {
            Text(prepError ?? "")
        }
        .alert("Couldn't Add to Calendar", isPresented: Binding(
            get: { calendarError != nil },
            set: { if !$0 { calendarError = nil } }
        )) {
            Button("OK") { calendarError = nil }
        } message: {
            Text(calendarError ?? "")
        }
    }

    // MARK: - Event Header

    private var eventHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: event.eventType.icon)
                    .font(.title)
                    .foregroundStyle(event.eventType.tint)

                VStack(alignment: .leading) {
                    Text(event.name)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(event.eventType.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
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

    // MARK: - AI Prep Generation

    private var prepGenerationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI EVENT PREP")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await generatePrep() }
                } label: {
                    if isGeneratingPrep {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Generate Prep", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingPrep)
            }

            Text("Generates a goal, elevator pitch, talking points, target companies, conversation starters, and things to avoid for this event.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Elevator Pitch

    private var elevatorPitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ELEVATOR PITCH")
                .font(.headline)
                .foregroundStyle(.secondary)

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
            Text("YOUR GOALS")
                .font(.headline)
                .foregroundStyle(.secondary)

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

    // MARK: - Talking Points

    private func talkingPointsSection(_ talkingPoints: [TalkingPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TALKING POINTS")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(talkingPoints) { point in
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.topic)
                        .fontWeight(.medium)
                    Text(point.relevance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Your angle: \(point.yourAngle)")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Target Companies

    private func targetCompaniesSection(_ targetCompanies: [TargetCompanyContext]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TARGET COMPANIES")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(targetCompanies) { company in
                VStack(alignment: .leading, spacing: 4) {
                    Text(company.company)
                        .fontWeight(.medium)
                    Text(company.whyRelevant)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let news = company.recentNews, !news.isEmpty {
                        Text("Recent news: \(news)")
                            .font(.caption)
                    }
                    if let roles = company.openRoles, !roles.isEmpty {
                        Text("Open roles: \(roles.joined(separator: ", "))")
                            .font(.caption)
                    }
                    if !company.possibleOpeners.isEmpty {
                        ForEach(company.possibleOpeners, id: \.self) { opener in
                            Label(opener, systemImage: "bubble.left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Conversation Starters

    private func conversationStartersSection(_ starters: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONVERSATION STARTERS")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(starters, id: \.self) { starter in
                Label(starter, systemImage: "bubble.left.and.bubble.right")
                    .font(.body)
                    .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Things to Avoid

    private func thingsToAvoidSection(_ thingsToAvoid: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THINGS TO AVOID")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(thingsToAvoid, id: \.self) { item in
                Label(item, systemImage: "exclamationmark.triangle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Contacts Section

    private var potentialContacts: [NetworkingContact] {
        coordinator.contactStore.allContacts.filter { contact in
            // Find contacts who might be at this event
            contact.warmth != .dormant && (
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
                        Text(contact.name)
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

    private func generatePrep() async {
        isGeneratingPrep = true
        defer { isGeneratingPrep = false }

        do {
            try await coordinator.prepareEvent(event)
            pitchText = event.pitchScript ?? ""
            goalText = event.goal ?? ""
        } catch {
            Logger.error("Failed to generate event prep: \(error)", category: .ai)
            prepError = "Couldn't generate event prep — \(error.localizedDescription)"
        }
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
                calendarError = "Couldn't add event to calendar — \(error.localizedDescription)"
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

