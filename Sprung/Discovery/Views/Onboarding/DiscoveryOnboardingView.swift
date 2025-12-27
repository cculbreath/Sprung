//
//  DiscoveryOnboardingView.swift
//  Sprung
//
//  Onboarding flow for Discovery module. Collects job search preferences
//  needed for LLM-powered task generation and source discovery.
//

import SwiftUI

struct DiscoveryOnboardingView: View {
    let coordinator: DiscoveryCoordinator
    let coverRefStore: CoverRefStore
    let applicantProfileStore: ApplicantProfileStore
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var selectedSectors: Set<String> = []
    @State private var customSector: String = ""
    @State private var location: String = ""
    @State private var remoteAcceptable: Bool = true
    @State private var preferredArrangement: WorkArrangement = .hybrid
    @State private var companySizePreference: CompanySizePreference = .any
    @State private var weeklyApplicationTarget: Int = 5
    @State private var weeklyNetworkingTarget: Int = 2
    @State private var isDiscovering: Bool = false
    @State private var discoveryError: String?

    // LLM-generated role suggestions
    @State private var suggestedRoles: [String] = []
    @State private var isLoadingSuggestions: Bool = false
    @State private var suggestionError: String?
    @State private var hasFetchedInitialSuggestions: Bool = false
    @State private var suggestionKeywords: String = ""

    // Background location preference extraction
    @State private var hasFetchedLocationPreferences: Bool = false
    @State private var isLoadingLocationPreferences: Bool = false

    private let commonSectors = [
        "Software Engineering",
        "Data Science / ML",
        "Product Management",
        "Design / UX",
        "DevOps / SRE",
        "Mobile Development",
        "Frontend Development",
        "Backend Development",
        "Full Stack Development",
        "Engineering Management",
        "Technical Writing",
        "QA / Testing",
        "Security",
        "Cloud / Infrastructure"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressBar

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case 0:
                        welcomeStep
                    case 1:
                        sectorsStep
                    case 2:
                        locationStep
                    case 3:
                        goalsStep
                    case 4:
                        setupStep
                    default:
                        EmptyView()
                    }
                }
                .padding(32)
            }

            Divider()

            // Navigation buttons
            navigationButtons
        }
        .frame(minWidth: 500, minHeight: 500)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progressFraction)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .frame(height: 4)
    }

    private var progressFraction: CGFloat {
        CGFloat(currentStep + 1) / 5.0
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to Discovery")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your AI-powered job search command center")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "checklist",
                    title: "Daily Task Management",
                    description: "AI-generated tasks prioritized for maximum impact"
                )

                FeatureRow(
                    icon: "link.circle",
                    title: "Smart Source Discovery",
                    description: "Find job boards and company pages tailored to your field"
                )

                FeatureRow(
                    icon: "calendar",
                    title: "Networking Events",
                    description: "Discover, evaluate, and prepare for networking opportunities"
                )

                FeatureRow(
                    icon: "person.2",
                    title: "Contact Management",
                    description: "Track relationships and get follow-up reminders"
                )

                FeatureRow(
                    icon: "chart.bar",
                    title: "Weekly Reviews",
                    description: "Reflect on progress with AI-powered insights"
                )
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Step 1: Sectors

    private var sectorsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What roles are you targeting?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select all that apply. This helps us find relevant job sources and events.")
                    .foregroundStyle(.secondary)
            }

            // 1. Selected roles (added titles) at top
            if !selectedSectors.isEmpty {
                selectedRolesSection
            }

            // 2. Custom entry box
            HStack {
                TextField("Add custom role...", text: $customSector)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addCustomSector()
                    }

                Button("Add") {
                    addCustomSector()
                }
                .disabled(customSector.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            // 3. LLM-suggested roles based on dossier
            if hasDossierData {
                suggestedRolesSection
            }

            // 4. Common sector options at bottom
            Text("Common Roles")
                .font(.headline)
                .padding(.top, 8)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(commonSectors, id: \.self) { sector in
                    SectorButton(
                        title: sector,
                        isSelected: selectedSectors.contains(sector),
                        action: { toggleSector(sector) }
                    )
                }
            }
        }
        .task {
            // Fetch role suggestions when entering this step
            if !hasFetchedInitialSuggestions && hasDossierData {
                await fetchRoleSuggestions()
                hasFetchedInitialSuggestions = true
            }

            // Fetch location preferences in background (for next step)
            if !hasFetchedLocationPreferences {
                await fetchLocationPreferences()
                hasFetchedLocationPreferences = true
            }
        }
    }

    // MARK: - Selected Roles Section

    private var selectedRolesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Roles")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(Array(selectedSectors).sorted(), id: \.self) { sector in
                    HStack(spacing: 4) {
                        Text(sector)
                        Button {
                            selectedSectors.remove(sector)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(16)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Suggested Roles Section

    private var hasDossierData: Bool {
        !coverRefStore.storedCoverRefs.filter { $0.isDossier }.isEmpty
    }

    private var suggestedRolesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Suggested for You", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.blue)

                Spacer()

                if isLoadingSuggestions {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Keyword input for guiding suggestions
            HStack {
                TextField("Keywords to explore (e.g., AI, healthcare, startups)...", text: $suggestionKeywords)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await fetchRoleSuggestions() }
                    }

                Button {
                    Task { await fetchRoleSuggestions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingSuggestions)
                .help("Generate suggestions based on your profile and keywords")
            }

            if let error = suggestionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if suggestedRoles.isEmpty && !isLoadingSuggestions {
                Text("Analyzing your profile...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(suggestedRoles.filter { !selectedSectors.contains($0) }, id: \.self) { role in
                        Button {
                            selectedSectors.insert(role)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption)
                                Text(role)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !suggestedRoles.filter({ selectedSectors.contains($0) }).isEmpty {
                    Text("✓ \(suggestedRoles.filter { selectedSectors.contains($0) }.count) suggestion(s) selected")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Role Suggestion Logic

    private func fetchRoleSuggestions() async {
        isLoadingSuggestions = true
        suggestionError = nil

        do {
            let summary = buildDossierSummary()
            let existingRoles = Array(selectedSectors)
            let keywords = suggestionKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
            suggestedRoles = try await coordinator.suggestTargetRoles(
                dossierSummary: summary,
                existingRoles: existingRoles,
                keywords: keywords.isEmpty ? nil : keywords
            )
            Logger.info("✨ Generated \(suggestedRoles.count) role suggestions", category: .ai)
        } catch {
            Logger.error("❌ Failed to generate role suggestions: \(error)", category: .ai)
            suggestionError = "Could not generate suggestions"
        }

        isLoadingSuggestions = false
    }

    private func buildDossierSummary() -> String {
        let dossierRefs = coverRefStore.storedCoverRefs.filter { $0.isDossier }

        var summary = ""

        for ref in dossierRefs {
            if !ref.name.isEmpty {
                summary += "**\(ref.name)**\n"
            }
            if !ref.content.isEmpty {
                // Include full dossier content (these are typically concise background facts)
                summary += "\(ref.content)\n\n"
            }
        }

        if summary.isEmpty {
            summary = "No detailed background available."
        }

        return summary
    }

    private func fetchLocationPreferences() async {
        isLoadingLocationPreferences = true

        // Build context from ApplicantProfile and dossier
        let profile = applicantProfileStore.currentProfile()
        let profileInfo = """
            Name: \(profile.name)
            City: \(profile.city)
            Address: \(profile.address)
            """

        let dossierSummary = buildDossierSummary()

        do {
            let result = try await coordinator.extractLocationPreferences(
                profileInfo: profileInfo,
                dossierSummary: dossierSummary
            )

            // Only update if the user hasn't already modified these fields
            if location.isEmpty, let extractedLocation = result.location {
                location = extractedLocation
            }
            if let extractedArrangement = result.workArrangement {
                preferredArrangement = extractedArrangement
            }
            if let extractedRemote = result.remoteAcceptable {
                remoteAcceptable = extractedRemote
            }
            if let extractedSize = result.companySize {
                companySizePreference = extractedSize
            }

            Logger.info("📍 Extracted preferences - location: \(result.location ?? "nil"), arrangement: \(result.workArrangement?.rawValue ?? "nil"), size: \(result.companySize?.rawValue ?? "nil")", category: .ai)
        } catch {
            Logger.warning("⚠️ Could not extract location preferences: \(error)", category: .ai)
            // Fall back to profile city if available
            let fallbackProfile = applicantProfileStore.currentProfile()
            if location.isEmpty && !fallbackProfile.city.isEmpty && fallbackProfile.city != "Sample City" {
                location = fallbackProfile.city
            }
        }

        isLoadingLocationPreferences = false
    }

    private func toggleSector(_ sector: String) {
        if selectedSectors.contains(sector) {
            selectedSectors.remove(sector)
        } else {
            selectedSectors.insert(sector)
        }
    }

    private func addCustomSector() {
        let trimmed = customSector.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selectedSectors.insert(trimmed)
        customSector = ""

        // Refresh suggestions with the new custom role context
        if hasDossierData {
            Task {
                await fetchRoleSuggestions()
            }
        }
    }

    // MARK: - Step 2: Location

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where are you looking for work?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This helps us find local job sources and networking events.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Primary Location")
                    .font(.headline)

                TextField("e.g., San Francisco Bay Area, Austin TX, Remote", text: $location)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(isOn: $remoteAcceptable) {
                VStack(alignment: .leading) {
                    Text("Open to remote positions")
                    Text("Include remote-only opportunities in search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Work Arrangement Preference")
                    .font(.headline)

                Picker("Arrangement", selection: $preferredArrangement) {
                    ForEach(WorkArrangement.allCases, id: \.self) { arrangement in
                        Text(arrangement.rawValue).tag(arrangement)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Company Size Preference")
                    .font(.headline)

                Picker("Size", selection: $companySizePreference) {
                    ForEach(CompanySizePreference.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Step 3: Goals

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set your weekly goals")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("These help us generate appropriate daily tasks and track your progress.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                GoalStepper(
                    title: "Applications per week",
                    value: $weeklyApplicationTarget,
                    range: 1...20,
                    icon: "paperplane",
                    color: .blue
                )

                GoalStepper(
                    title: "Networking events per week",
                    value: $weeklyNetworkingTarget,
                    range: 0...10,
                    icon: "person.2",
                    color: .orange
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tip")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Start with achievable goals. You can adjust these anytime in settings. Consistency beats intensity in a job search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Step 4: Setup

    private var setupStep: some View {
        VStack(spacing: 24) {
            if isDiscovering {
                AnimatedThinkingText(statusMessage: "Discovering job sources and generating tasks...")

                // Show dynamic status from coordinator
                Text(coordinator.discoveryStatus.message.isEmpty ? "Setting up your job search" : coordinator.discoveryStatus.message)
                    .font(.title3)
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.3), value: coordinator.discoveryStatus.message)
            } else if let error = discoveryError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Setup encountered an issue")
                    .font(.title3)

                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Continue Anyway") {
                    completeOnboarding()
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("You're all set!")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingSummaryRow(label: "Target roles", value: selectedSectors.joined(separator: ", "))
                    OnboardingSummaryRow(label: "Location", value: location)
                    OnboardingSummaryRow(label: "Weekly apps target", value: "\(weeklyApplicationTarget)")
                    OnboardingSummaryRow(label: "Weekly events target", value: "\(weeklyNetworkingTarget)")
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Text("Click \"Get Started\" to discover job sources and generate your first daily tasks.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < 4 {
                Button("Continue") {
                    withAnimation {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            } else {
                Button("Get Started") {
                    Task { await startSetup() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDiscovering)
            }
        }
        .padding()
    }

    private var canContinue: Bool {
        switch currentStep {
        case 1:
            return !selectedSectors.isEmpty
        case 2:
            return !location.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    // MARK: - Actions

    private func startSetup() async {
        isDiscovering = true
        discoveryError = nil

        // Save preferences
        var prefs = coordinator.preferencesStore.current()
        prefs.targetSectors = Array(selectedSectors)
        prefs.primaryLocation = location
        prefs.remoteAcceptable = remoteAcceptable
        prefs.preferredArrangement = preferredArrangement
        prefs.companySizePreference = companySizePreference
        prefs.weeklyApplicationTarget = weeklyApplicationTarget
        prefs.weeklyNetworkingTarget = weeklyNetworkingTarget
        coordinator.preferencesStore.update(prefs)

        // Update weekly goal
        let goal = coordinator.weeklyGoalStore.currentWeek()
        goal.applicationTarget = weeklyApplicationTarget
        goal.eventsAttendedTarget = weeklyNetworkingTarget

        // Try to discover sources and generate tasks
        do {
            try await coordinator.discoverJobSources()
            try await coordinator.generateDailyTasks()
            completeOnboarding()
        } catch {
            Logger.error("Onboarding setup failed: \(error)", category: .ai)
            discoveryError = "Could not connect to AI service. You can discover sources manually later."
        }

        isDiscovering = false
    }

    private func completeOnboarding() {
        onComplete()
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SectorButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private struct GoalStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)

            Spacer()

            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 30)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct OnboardingSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
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
