import Foundation
import SwiftyJSON

/// Service responsible for persisting onboarding data: writing samples, dossier, and experience defaults.
/// Extracted from CoordinatorEventRouter to improve separation of concerns.
@MainActor
final class OnboardingPersistenceService {
    private let ui: OnboardingUIState
    private let dataStore: InterviewDataStore
    private let coverRefStore: CoverRefStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    private let eventBus: EventCoordinator
    private let artifactRecordStore: ArtifactRecordStore
    private let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler

    init(
        ui: OnboardingUIState,
        dataStore: InterviewDataStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        eventBus: EventCoordinator,
        artifactRecordStore: ArtifactRecordStore,
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    ) {
        self.ui = ui
        self.dataStore = dataStore
        self.coverRefStore = coverRefStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.eventBus = eventBus
        self.artifactRecordStore = artifactRecordStore
        self.sessionPersistenceHandler = sessionPersistenceHandler
    }

    /// Typed artifacts for the current session
    private var sessionWritingSamples: [ArtifactRecord] {
        guard let session = sessionPersistenceHandler.currentSession else { return [] }
        return artifactRecordStore.artifacts(for: session).filter { $0.isWritingSample }
    }

    // MARK: - Writing Corpus Persistence

    /// Persist writing samples to CoverRefStore and candidate dossier to ResRefStore when interview completes
    func persistWritingCorpusOnComplete() async {
        Logger.info("💾 [persistWritingCorpus] START - Persisting writing corpus and dossier on interview completion", category: .ai)

        // Get writing samples from typed ArtifactRecord store
        let writingSamples = sessionWritingSamples
        Logger.info("💾 [persistWritingCorpus] Found \(writingSamples.count) writing samples in session", category: .ai)

        // Debug: Log all writing sample filenames
        for (index, sample) in writingSamples.enumerated() {
            Logger.debug("💾 [persistWritingCorpus] WritingSample[\(index)]: filename='\(sample.filename)' sourceType='\(sample.sourceType)'", category: .ai)
        }

        for sample in writingSamples {
            persistWritingSampleToCoverRef(sample: sample)
        }

        Logger.info("✅ [persistWritingCorpus] Persisted \(writingSamples.count) writing samples to CoverRefStore", category: .ai)

        // Delete writing sample artifacts from session after persisting
        // They've been copied to CoverRefStore and are no longer needed
        for sample in writingSamples {
            artifactRecordStore.deleteArtifact(sample)
        }
        Logger.info("🗑️ [persistWritingCorpus] Deleted \(writingSamples.count) writing sample artifacts from session", category: .ai)

        // Note: Candidate dossier is persisted directly to CandidateDossierStore by SubmitCandidateDossierTool

        // Emit events for persistence completion
        await eventBus.publish(.artifact(.writingSamplePersisted(sample: JSON(["count": writingSamples.count]))))
        Logger.info("💾 [persistWritingCorpus] END - Persistence complete", category: .ai)
    }

    /// Convert a writing sample artifact to CoverRef and persist
    private func persistWritingSampleToCoverRef(sample: ArtifactRecord) {
        let name = sample.metadataString("name") ??
                   sample.filename.replacingOccurrences(of: ".txt", with: "")
        let content = sample.extractedContent

        // Skip if no content
        guard !content.isEmpty else {
            Logger.warning("⚠️ Skipping writing sample with empty content: \(name)", category: .ai)
            return
        }

        let coverRef = CoverRef(
            name: name,
            content: content,
            enabledByDefault: true,
            type: .writingSample
        )

        coverRefStore.addCoverRef(coverRef)
        Logger.info("💾 Writing sample persisted to CoverRef: \(name)", category: .ai)
    }

    // MARK: - Experience Defaults Propagation

    /// Propagate timeline cards to ExperienceDefaults when interview completes.
    /// Skips sections that already have agent-generated content to avoid duplicates.
    func propagateExperienceDefaults() async {
        Logger.info("📋 Propagating timeline cards to ExperienceDefaults", category: .ai)

        guard let timeline = ui.skeletonTimeline,
              let experiences = timeline["experiences"].array else {
            Logger.warning("⚠️ No timeline experiences to propagate", category: .ai)
            return
        }

        // Load current draft
        var draft = experienceDefaultsStore.loadDraft()

        // Track what already has agent-generated content (with highlights)
        let hasAgentWork = draft.work.contains { !$0.highlights.isEmpty }
        let hasAgentEducation = !draft.education.isEmpty
        let hasAgentVolunteer = !draft.volunteer.isEmpty
        // Note: projects come from KCs not timeline, so always allow propagation

        var propagatedCount = 0

        // Process each timeline card based on experienceType
        for card in experiences {
            let experienceType = card["experienceType"].string ?? "work"

            switch experienceType {
            case "work":
                // Skip if agent already generated work entries with highlights
                if hasAgentWork {
                    Logger.info("📋 Skipping work propagation - agent already generated work with highlights", category: .ai)
                    continue
                }
                let workDraft = createWorkExperienceDraft(from: card)
                draft.work.append(workDraft)
                draft.isWorkEnabled = true
                propagatedCount += 1

            case "education":
                // Skip if agent already generated education entries
                if hasAgentEducation {
                    continue
                }
                let eduDraft = createEducationDraft(from: card)
                draft.education.append(eduDraft)
                draft.isEducationEnabled = true
                propagatedCount += 1

            case "volunteer":
                // Skip if agent already generated volunteer entries
                if hasAgentVolunteer {
                    continue
                }
                let volDraft = createVolunteerDraft(from: card)
                draft.volunteer.append(volDraft)
                draft.isVolunteerEnabled = true
                propagatedCount += 1

            case "project":
                // Projects come from KCs, not timeline - this case shouldn't happen often
                let projDraft = createProjectDraft(from: card)
                draft.projects.append(projDraft)
                draft.isProjectsEnabled = true
                propagatedCount += 1

            default:
                if !hasAgentWork {
                    let workDraft = createWorkExperienceDraft(from: card)
                    draft.work.append(workDraft)
                    draft.isWorkEnabled = true
                    propagatedCount += 1
                }
            }
        }

        // Save the draft
        experienceDefaultsStore.save(draft: draft)
        if propagatedCount > 0 {
            Logger.info("✅ Propagated \(propagatedCount) timeline cards to ExperienceDefaults", category: .ai)
        } else {
            Logger.info("✅ No propagation needed - agent already generated content", category: .ai)
        }
    }

    // MARK: - Timeline Card Draft Converters

    private func createWorkExperienceDraft(from card: JSON) -> WorkExperienceDraft {
        var draft = WorkExperienceDraft()
        draft.name = card["organization"].stringValue
        draft.position = card["title"].stringValue
        draft.location = card["location"].stringValue
        draft.url = card["url"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        draft.summary = card["summary"].stringValue
        draft.highlights = card["highlights"].arrayValue.map { highlight in
            var h = HighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createEducationDraft(from card: JSON) -> EducationExperienceDraft {
        var draft = EducationExperienceDraft()
        draft.institution = card["organization"].stringValue
        draft.url = card["url"].stringValue
        draft.area = card["title"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        return draft
    }

    private func createVolunteerDraft(from card: JSON) -> VolunteerExperienceDraft {
        var draft = VolunteerExperienceDraft()
        draft.organization = card["organization"].stringValue
        draft.position = card["title"].stringValue
        draft.url = card["url"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        draft.summary = card["summary"].stringValue
        draft.highlights = card["highlights"].arrayValue.map { highlight in
            var h = VolunteerHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createProjectDraft(from card: JSON) -> ProjectExperienceDraft {
        var draft = ProjectExperienceDraft()
        draft.name = card["title"].stringValue
        draft.description = card["summary"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        draft.url = card["url"].stringValue
        draft.organization = card["organization"].stringValue
        draft.highlights = card["highlights"].arrayValue.map { highlight in
            var h = ProjectHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    // MARK: - LLM-Generated Experience Defaults

    /// Handle experience defaults generated by LLM from knowledge cards
    func handleExperienceDefaultsGenerated(_ defaults: JSON) async {
        Logger.info("📋 Processing LLM-generated experience defaults", category: .ai)

        var draft = ExperienceDefaultsDraft()

        // Process work experiences
        if let workArray = defaults["work"].array, !workArray.isEmpty {
            draft.isWorkEnabled = true
            draft.work = workArray.map { createWorkDraftFromLLM($0) }
            Logger.info("📋 Added \(workArray.count) work experiences", category: .ai)
        }

        // Process education
        if let eduArray = defaults["education"].array, !eduArray.isEmpty {
            draft.isEducationEnabled = true
            draft.education = eduArray.map { createEducationDraftFromLLM($0) }
            Logger.info("📋 Added \(eduArray.count) education entries", category: .ai)
        }

        // Process projects
        if let projArray = defaults["projects"].array, !projArray.isEmpty {
            draft.isProjectsEnabled = true
            draft.projects = projArray.map { createProjectDraftFromLLM($0) }
            Logger.info("📋 Added \(projArray.count) projects", category: .ai)
        }

        // Process skills
        if let skillsArray = defaults["skills"].array, !skillsArray.isEmpty {
            draft.isSkillsEnabled = true
            draft.skills = skillsArray.map { createSkillDraftFromLLM($0) }
            Logger.info("📋 Added \(skillsArray.count) skill categories", category: .ai)
        }

        // Process languages
        if let langArray = defaults["languages"].array, !langArray.isEmpty {
            draft.isLanguagesEnabled = true
            draft.languages = langArray.map { createLanguageDraftFromLLM($0) }
            Logger.info("📋 Added \(langArray.count) languages", category: .ai)
        }

        // Process volunteer experiences
        if let volArray = defaults["volunteer"].array, !volArray.isEmpty {
            draft.isVolunteerEnabled = true
            draft.volunteer = volArray.map { createVolunteerDraftFromLLM($0) }
            Logger.info("📋 Added \(volArray.count) volunteer experiences", category: .ai)
        }

        // Process awards
        if let awardsArray = defaults["awards"].array, !awardsArray.isEmpty {
            draft.isAwardsEnabled = true
            draft.awards = awardsArray.map { createAwardDraftFromLLM($0) }
            Logger.info("📋 Added \(awardsArray.count) awards", category: .ai)
        }

        // Process certificates
        if let certsArray = defaults["certificates"].array, !certsArray.isEmpty {
            draft.isCertificatesEnabled = true
            draft.certificates = certsArray.map { createCertificateDraftFromLLM($0) }
            Logger.info("📋 Added \(certsArray.count) certificates", category: .ai)
        }

        // Process publications - section cards are authoritative
        let sectionCardPublications = ui.publicationCards
        if !sectionCardPublications.isEmpty {
            // Section cards exist - use them as the source of truth
            draft.isPublicationsEnabled = true
            draft.publications = sectionCardPublications.map { createPublicationDraftFromCard($0) }

            // Log if LLM output differs from section cards
            let llmPubCount = defaults["publications"].array?.count ?? 0
            if llmPubCount != sectionCardPublications.count {
                Logger.warning("📋 Publications mismatch: LLM generated \(llmPubCount), section cards have \(sectionCardPublications.count). Using section cards.", category: .ai)
            }
            Logger.info("📋 Added \(sectionCardPublications.count) publications from section cards", category: .ai)
        } else if let pubsArray = defaults["publications"].array, !pubsArray.isEmpty {
            // No section cards - fall back to LLM output
            draft.isPublicationsEnabled = true
            draft.publications = pubsArray.map { createPublicationDraftFromLLM($0) }
            Logger.info("📋 Added \(pubsArray.count) publications from LLM", category: .ai)
        }

        // Process custom fields (keys starting with "custom.")
        // LLM can send either scalar strings or arrays of strings
        var customFields: [CustomFieldValue] = []
        if let dict = defaults.dictionary {
            for (key, value) in dict where key.hasPrefix("custom.") {
                // Extract the field key (keep the full key including "custom." prefix for clarity)
                let fieldKey = key

                var values: [String] = []
                if let stringValue = value.string {
                    // Scalar value - wrap in array
                    values = [stringValue]
                } else if let arrayValue = value.array {
                    // Array value - extract string values
                    values = arrayValue.compactMap { $0.string }
                }

                if !values.isEmpty {
                    let customField = CustomFieldValue(key: fieldKey, values: values)
                    customFields.append(customField)
                    Logger.info("📋 Added custom field '\(fieldKey)' with \(values.count) value(s)", category: .ai)
                }
            }
        }

        if !customFields.isEmpty {
            draft.customFields = customFields
            draft.isCustomEnabled = true
        }

        // Save the draft to ExperienceDefaultsStore
        experienceDefaultsStore.save(draft: draft)
        Logger.info("✅ Saved LLM-generated experience defaults to store", category: .ai)

        // Persist to InterviewDataStore for phase completion gating
        do {
            let persistedId = try await dataStore.persist(dataType: "experience_defaults", payload: defaults)
            Logger.info("💾 Persisted experience_defaults for phase completion (\(persistedId))", category: .ai)
        } catch {
            Logger.error("❌ Failed to persist experience_defaults to data store: \(error.localizedDescription)", category: .ai)
        }

        // Mark objective as completed so subphase can advance to p4_completion
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.experienceDefaultsSet.rawValue,
            status: "completed",
            source: "persistence_service",
            notes: "Experience defaults generated and persisted",
            details: nil
        )))
    }

    // MARK: - LLM JSON to Draft Converters

    private func createWorkDraftFromLLM(_ json: JSON) -> WorkExperienceDraft {
        var draft = WorkExperienceDraft()
        draft.name = json["name"].stringValue
        draft.position = json["position"].stringValue
        draft.location = json["location"].stringValue
        draft.url = json["url"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.summary = json["summary"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { highlight in
            var h = HighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createEducationDraftFromLLM(_ json: JSON) -> EducationExperienceDraft {
        var draft = EducationExperienceDraft()
        draft.institution = json["institution"].stringValue
        draft.url = json["url"].stringValue
        draft.area = json["area"].stringValue
        draft.studyType = json["studyType"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.score = json["score"].stringValue
        draft.courses = json["courses"].arrayValue.map { course in
            var c = CourseDraft()
            c.name = course.stringValue
            return c
        }
        return draft
    }

    private func createProjectDraftFromLLM(_ json: JSON) -> ProjectExperienceDraft {
        var draft = ProjectExperienceDraft()
        draft.name = json["name"].stringValue
        draft.description = json["description"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.url = json["url"].stringValue
        draft.organization = json["organization"].stringValue
        draft.type = json["type"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { highlight in
            var h = ProjectHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        draft.keywords = json["keywords"].arrayValue.map { kw in
            KeywordDraft(keyword: kw.stringValue)
        }
        draft.roles = json["roles"].arrayValue.map { role in
            RoleDraft(role: role.stringValue)
        }
        return draft
    }

    private func createSkillDraftFromLLM(_ json: JSON) -> SkillExperienceDraft {
        var draft = SkillExperienceDraft()
        draft.name = json["name"].stringValue
        draft.level = json["level"].stringValue
        draft.keywords = json["keywords"].arrayValue.map { kw in
            KeywordDraft(keyword: kw.stringValue)
        }
        return draft
    }

    private func createLanguageDraftFromLLM(_ json: JSON) -> LanguageExperienceDraft {
        var draft = LanguageExperienceDraft()
        draft.language = json["language"].stringValue
        draft.fluency = json["fluency"].stringValue
        return draft
    }

    private func createVolunteerDraftFromLLM(_ json: JSON) -> VolunteerExperienceDraft {
        var draft = VolunteerExperienceDraft()
        draft.organization = json["organization"].stringValue
        draft.position = json["position"].stringValue
        draft.url = json["url"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.summary = json["summary"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { highlight in
            var h = VolunteerHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createAwardDraftFromLLM(_ json: JSON) -> AwardExperienceDraft {
        var draft = AwardExperienceDraft()
        draft.title = json["title"].stringValue
        draft.date = json["date"].stringValue
        draft.awarder = json["awarder"].stringValue
        draft.summary = json["summary"].stringValue
        return draft
    }

    private func createCertificateDraftFromLLM(_ json: JSON) -> CertificateExperienceDraft {
        var draft = CertificateExperienceDraft()
        draft.name = json["name"].stringValue
        draft.date = json["date"].stringValue
        draft.issuer = json["issuer"].stringValue
        draft.url = json["url"].stringValue
        return draft
    }

    private func createPublicationDraftFromLLM(_ json: JSON) -> PublicationExperienceDraft {
        var draft = PublicationExperienceDraft()
        draft.name = json["name"].stringValue
        draft.publisher = json["publisher"].stringValue
        draft.releaseDate = json["releaseDate"].stringValue
        draft.url = json["url"].stringValue
        draft.summary = json["summary"].stringValue
        return draft
    }

    private func createPublicationDraftFromCard(_ card: PublicationCard) -> PublicationExperienceDraft {
        var draft = PublicationExperienceDraft()
        draft.name = card.name
        draft.publisher = card.publisher
        draft.releaseDate = card.releaseDate
        draft.url = card.url
        draft.summary = card.summary
        return draft
    }
}
