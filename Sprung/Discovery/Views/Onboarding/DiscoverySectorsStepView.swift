//
//  DiscoverySectorsStepView.swift
//  Sprung
//
//  Step 1 of Discovery onboarding: role selection, LLM suggestions,
//  background location prefetch.
//

import SwiftUI

struct DiscoverySectorsStepView: View {
    let coordinator: DiscoveryCoordinator
    let candidateDossierStore: CandidateDossierStore
    let applicantProfileStore: ApplicantProfileStore

    @Binding var selectedSectors: Set<String>
    @Binding var location: String
    @Binding var remoteAcceptable: Bool
    @Binding var preferredArrangement: WorkArrangement
    @Binding var companySizePreference: CompanySizePreference

    @State private var customSector: String = ""
    @State private var suggestedRoles: [String] = []
    @State private var isLoadingSuggestions: Bool = false
    @State private var suggestionError: String?
    @State private var hasFetchedInitialSuggestions: Bool = false
    @State private var suggestionKeywords: String = ""
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

            FlowStack(spacing: 8) {
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
        candidateDossierStore.hasDossier
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
                FlowStack(spacing: 8) {
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
                    Text("\u{2713} \(suggestedRoles.filter { selectedSectors.contains($0) }.count) suggestion(s) selected")
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
            Logger.info("Generated \(suggestedRoles.count) role suggestions", category: .ai)
        } catch {
            Logger.error("Failed to generate role suggestions: \(error)", category: .ai)
            suggestionError = "Could not generate suggestions"
        }

        isLoadingSuggestions = false
    }

    private func buildDossierSummary() -> String {
        candidateDossierStore.dossier?.exportForDiscovery() ?? "No detailed background available."
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

            Logger.info("Extracted preferences - location: \(result.location ?? "nil"), arrangement: \(result.workArrangement?.rawValue ?? "nil"), size: \(result.companySize?.rawValue ?? "nil")", category: .ai)
        } catch {
            Logger.warning("Could not extract location preferences: \(error)", category: .ai)
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
}
