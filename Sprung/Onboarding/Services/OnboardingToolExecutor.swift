import Foundation
import SwiftyJSON

@MainActor
final class OnboardingToolExecutor {
    private let artifactStore: OnboardingArtifactStore
    private let applicantProfileStore: ApplicantProfileStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    private weak var coverRefStore: CoverRefStore?
    private let uploadRegistry: OnboardingUploadRegistry
    private let artifactValidator: OnboardingArtifactValidator
    private let allowWebSearch: () -> Bool
    private let allowWritingAnalysis: () -> Bool
    private let refreshArtifacts: () -> Void
    private let setPendingExtraction: (OnboardingPendingExtraction?) -> Void

    init(
        artifactStore: OnboardingArtifactStore,
        applicantProfileStore: ApplicantProfileStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        coverRefStore: CoverRefStore?,
        uploadRegistry: OnboardingUploadRegistry,
        artifactValidator: OnboardingArtifactValidator,
        allowWebSearch: @escaping () -> Bool,
        allowWritingAnalysis: @escaping () -> Bool,
        refreshArtifacts: @escaping () -> Void,
        setPendingExtraction: @escaping (OnboardingPendingExtraction?) -> Void
    ) {
        self.artifactStore = artifactStore
        self.applicantProfileStore = applicantProfileStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.coverRefStore = coverRefStore
        self.uploadRegistry = uploadRegistry
        self.artifactValidator = artifactValidator
        self.allowWebSearch = allowWebSearch
        self.allowWritingAnalysis = allowWritingAnalysis
        self.refreshArtifacts = refreshArtifacts
        self.setPendingExtraction = setPendingExtraction
    }

    func execute(_ call: OnboardingToolCall) async throws -> JSON {
        switch call.tool {
        case "parse_resume":
            return try executeParseResume(call)
        case "parse_linkedin":
            return try await executeParseLinkedIn(call)
        case "summarize_artifact":
            return try executeSummarizeArtifact(call)
        case "summarize_writing":
            return try executeSummarizeWriting(call)
        case "web_lookup":
            return try await executeWebLookup(call)
        case "persist_delta":
            try await executePersistDelta(call)
            return JSON(["status": "saved"])
        case "persist_card":
            try executePersistCard(call)
            return JSON(["status": "saved"])
        case "persist_skill_map":
            try executePersistSkillMap(call)
            return JSON(["status": "saved"])
        case "persist_facts_from_card":
            try executePersistFactsFromCard(call)
            return JSON(["status": "saved"])
        case "persist_style_profile":
            try executePersistStyleProfile(call)
            return JSON(["status": "saved"])
        case "verify_conflicts":
            return try executeVerifyConflicts()
        case "prompt_user_for_upload":
            return JSON([
                "status": "awaiting_user"
            ])
        default:
            throw OnboardingInterviewService.OnboardingError.unsupportedTool(call.tool)
        }
    }

    func applyDeltaUpdates(_ updates: [JSON]) async throws {
        for update in updates {
            if let target = update["target"].string {
                let value = update["value"]
                try await applyPatch(target: target, patch: value)
            } else {
                let profilePatch = update["applicant_profile_patch"]
                if profilePatch.type != .null {
                    try await applyPatch(target: "applicant_profile", patch: profilePatch)
                }

                let defaultPatch = update["default_values_patch"]
                if defaultPatch.type != .null {
                    try await applyPatch(target: "default_values", patch: defaultPatch)
                }
            }
        }
    }

    func applyPatch(target: String, patch: JSON) async throws {
        let normalized = target.lowercased()
        switch normalized {
        case "applicant_profile":
            let merged = artifactStore.mergeApplicantProfile(patch: patch)
            applyApplicantProfilePatch(merged)
        case "default_values":
            let merged = artifactStore.mergeDefaultValues(patch: patch)
            if merged.type == .dictionary {
                let draft = ExperienceDefaultsDecoder.draft(from: merged)
                experienceDefaultsStore.save(draft: draft)
            }
        case "skill_map", "skills_index":
            _ = artifactStore.mergeSkillMap(patch: patch)
        case "fact_ledger":
            if let entries = patch.array {
                _ = artifactStore.appendFactLedgerEntries(entries)
            }
        case "style_profile":
            artifactStore.saveStyleProfile(patch)
        case "writing_samples":
            if let entries = patch.array {
                _ = artifactStore.saveWritingSamples(entries)
                persistWritingSamplesToCoverRefs(samples: entries)
            }
        default:
            Logger.warning("OnboardingToolExecutor: unhandled delta target \(target)")
        }
        refreshArtifacts()
    }

    func saveWritingSamples(_ samples: [JSON]) {
        guard !samples.isEmpty else { return }
        _ = artifactStore.saveWritingSamples(samples)
        persistWritingSamplesToCoverRefs(samples: samples)
    }

    // MARK: - Individual Tools

    private func executeParseResume(_ call: OnboardingToolCall) throws -> JSON {
        guard let fileId = call.arguments["fileId"].string,
              let upload = uploadRegistry.upload(withId: fileId),
              let data = upload.data else {
            throw OnboardingInterviewService.OnboardingError.missingResource("resume file")
        }

        let extraction = ResumeRawExtractor.extract(from: data, filename: upload.name)
        let uncertainties = ["education", "experience"].filter { extraction[$0].type == .null }

        setPendingExtraction(OnboardingPendingExtraction(rawExtraction: extraction, uncertainties: uncertainties))

        return JSON([
            "status": "awaiting_confirmation",
            "raw_extraction": extraction,
            "uncertainties": JSON(uncertainties)
        ])
    }

    private func executeParseLinkedIn(_ call: OnboardingToolCall) async throws -> JSON {
        if let directURL = call.arguments["url"].string, let url = URL(string: directURL) {
            let result = try await LinkedInProfileExtractor.extract(from: url)
            return JSON([
                "status": "complete",
                "raw_extraction": result.extraction,
                "uncertainties": JSON(result.uncertainties)
            ])
        }

        if let fileId = call.arguments["fileId"].string,
           let upload = uploadRegistry.upload(withId: fileId) {
            if let url = upload.url {
                let result = try await LinkedInProfileExtractor.extract(from: url)
                return JSON([
                    "status": "complete",
                    "raw_extraction": result.extraction,
                    "uncertainties": JSON(result.uncertainties)
                ])
            }
            if let data = upload.data, let string = String(data: data, encoding: .utf8) {
                let result = try LinkedInProfileExtractor.parse(html: string, source: upload.name)
                return JSON([
                    "status": "complete",
                    "raw_extraction": result.extraction,
                    "uncertainties": JSON(result.uncertainties)
                ])
            }
        }

        throw OnboardingInterviewService.OnboardingError.missingResource("LinkedIn content")
    }

    private func executeSummarizeArtifact(_ call: OnboardingToolCall) throws -> JSON {
        guard let fileId = call.arguments["fileId"].string,
              let upload = uploadRegistry.upload(withId: fileId),
              let data = upload.data else {
            throw OnboardingInterviewService.OnboardingError.missingResource("artifact data")
        }

        let context = call.arguments["context"].string
        let card = ArtifactSummarizer.summarize(data: data, filename: upload.name, context: context)
        _ = artifactStore.appendKnowledgeCards([card])
        refreshArtifacts()
        return card
    }

    private func executeSummarizeWriting(_ call: OnboardingToolCall) throws -> JSON {
        guard allowWritingAnalysis() else {
            throw OnboardingInterviewService.OnboardingError.writingAnalysisNotAllowed
        }
        guard let fileId = call.arguments["fileId"].string,
              let upload = uploadRegistry.upload(withId: fileId),
              let data = upload.data else {
            throw OnboardingInterviewService.OnboardingError.missingResource("writing sample data")
        }

        let context = call.arguments["context"].string
        let summary = WritingSampleAnalyzer.analyze(
            data: data,
            filename: upload.name,
            context: context,
            sampleId: fileId
        )
        _ = artifactStore.saveWritingSamples([summary])
        persistWritingSamplesToCoverRefs(samples: [summary])
        refreshArtifacts()
        return summary
    }

    private func executeWebLookup(_ call: OnboardingToolCall) async throws -> JSON {
        guard allowWebSearch() else {
            throw OnboardingInterviewService.OnboardingError.webSearchNotAllowed
        }
        guard let query = call.arguments["query"].string, !query.isEmpty else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("Missing query for web_lookup")
        }

        let result = try await WebLookupService.search(query: query)
        return JSON([
            "results": JSON(result.entries),
            "notices": JSON(result.notices)
        ])
    }

    private func executePersistFactsFromCard(_ call: OnboardingToolCall) throws {
        let factsArray = call.arguments["facts"].array ??
            call.arguments["entries"].array ??
            call.arguments["fact_ledger"].array ?? []
        guard !factsArray.isEmpty else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("persist_facts_from_card expects non-empty facts array")
        }

        let validation = SchemaValidator.validateFactLedger(factsArray)
        guard validation.errors.isEmpty else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("Fact ledger validation failed: \(validation.errors.joined(separator: "; "))")
        }

        _ = artifactStore.appendFactLedgerEntries(factsArray)
        refreshArtifacts()
    }

    private func executePersistStyleProfile(_ call: OnboardingToolCall) throws {
        guard allowWritingAnalysis() else {
            throw OnboardingInterviewService.OnboardingError.writingAnalysisNotAllowed
        }

        let styleVector = call.arguments["style_vector"]
        guard styleVector.type == .dictionary else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("Style profile requires style_vector object")
        }

        let samplesJSON = call.arguments["samples"]
        guard let sampleArray = samplesJSON.array, !sampleArray.isEmpty else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("Style profile requires at least one writing sample reference")
        }

        var payloadDictionary: [String: Any] = [:]
        payloadDictionary["style_vector"] = styleVector.dictionaryObject ?? styleVector.object
        payloadDictionary["samples"] = samplesJSON.arrayObject ?? []

        let payload = JSON(payloadDictionary)
        let validation = SchemaValidator.validateStyleProfile(payload)
        guard validation.errors.isEmpty else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("Style profile validation failed: \(validation.errors.joined(separator: "; "))")
        }

        artifactStore.saveStyleProfile(payload)
        _ = artifactStore.saveWritingSamples(sampleArray)
        persistWritingSamplesToCoverRefs(samples: sampleArray)

        refreshArtifacts()
    }

    private func persistWritingSamplesToCoverRefs(samples: [JSON]) {
        guard let coverRefStore else { return }
        var didPersist = false

        for sample in samples {
            guard let sampleId = sample["sample_id"].string ?? sample["id"].string,
                  let upload = uploadRegistry.upload(withId: sampleId),
                  let data = upload.data else {
                continue
            }

            let name = sample["title"].string ??
                sample["name"].string ??
                upload.name
            let content = WritingSampleAnalyzer.extractPlainText(from: data)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if let existing = coverRefStore.storedCoverRefs.first(where: { $0.id == sampleId }) {
                existing.content = content
                existing.name = name
                didPersist = coverRefStore.saveContext() || didPersist
            } else {
                let newRef = CoverRef(name: name, content: content, enabledByDefault: false, type: .writingSample)
                newRef.id = sampleId
                coverRefStore.addCoverRef(newRef)
                didPersist = true
            }
        }

        if didPersist {
            Logger.info("✅ Persisted writing samples to CoverRef store.")
        }
    }

    private func executeVerifyConflicts() throws -> JSON {
        let latest = artifactStore.loadArtifacts()
        guard let defaultValues = latest.defaultValues else {
            return JSON([
                "status": "complete",
                "conflicts": []
            ])
        }

        let conflicts = artifactValidator.timelineConflicts(in: defaultValues)
        let status = conflicts.isEmpty ? "none" : "conflicts_found"
        return JSON([
            "status": status,
            "conflicts": JSON(conflicts)
        ])
    }

    private func executePersistDelta(_ call: OnboardingToolCall) async throws {
        guard let target = call.arguments["target"].string else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("persist_delta missing target")
        }
        let delta = call.arguments["delta"]
        let valueFallback = call.arguments["value"]
        let payload = delta.type == .null ? valueFallback : delta
        guard payload.type != .null else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("persist_delta requires delta or value payload")
        }
        try await applyPatch(target: target, patch: payload)
    }

    private func executePersistCard(_ call: OnboardingToolCall) throws {
        let card = call.arguments["card"]
        guard card.type == .dictionary else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("persist_card expects card object")
        }
        _ = artifactStore.appendKnowledgeCards([card])
        refreshArtifacts()
    }

    private func executePersistSkillMap(_ call: OnboardingToolCall) throws {
        let delta = call.arguments["skillMapDelta"]
        guard delta.type == .dictionary else {
            throw OnboardingInterviewService.OnboardingError.invalidArguments("persist_skill_map expects skillMapDelta object")
        }
        _ = artifactStore.mergeSkillMap(patch: delta)
        refreshArtifacts()
    }

    private func applyApplicantProfilePatch(_ patch: JSON) {
        guard patch.type == .dictionary else { return }

        let profile = applicantProfileStore.currentProfile()

        if let name = patch["name"].string?.trimmed() { profile.name = name }
        if let label = patch["label"].string?.trimmed() { profile.label = label }
        if let summary = patch["summary"].string { profile.summary = summary }
        if let address = patch["address"].string?.trimmed() { profile.address = address }
        if let city = patch["city"].string?.trimmed() { profile.city = city }
        if let state = patch["state"].string?.trimmed() { profile.state = state }
        if let zip = patch["zip"].string?.trimmed() { profile.zip = zip }
        if let phone = patch["phone"].string?.trimmed() { profile.phone = phone }
        if let email = patch["email"].string?.trimmed() { profile.email = email }
        if let website = patch["website"].string?.trimmed() { profile.websites = website }
        if let country = patch["country_code"].string?.trimmed() ?? patch["country"].string?.trimmed() {
            profile.countryCode = country
        }

        if let location = patch["location"].dictionary {
            if let address = location["address"]?.string?.trimmed() { profile.address = address }
            if let city = location["city"]?.string?.trimmed() { profile.city = city }
            if let state = location["region"]?.string?.trimmed() ?? location["state"]?.string?.trimmed() {
                profile.state = state
            }
            if let postal = location["postalCode"]?.string?.trimmed() ?? location["zip"]?.string?.trimmed() ?? location["code"]?.string?.trimmed() {
                profile.zip = postal
            }
            if let country = location["countryCode"]?.string?.trimmed() { profile.countryCode = country }
        }

        if let profilesArray = patch["profiles"].array {
            mergeSocialProfiles(from: profilesArray, into: profile)
        }

        if let signatureBase64 = patch["signature_image"].string,
           let data = Data(base64Encoded: signatureBase64) {
            profile.signatureData = data
        }

        applicantProfileStore.save(profile)
    }

    private func mergeSocialProfiles(from jsonArray: [JSON], into profile: ApplicantProfile) {
        guard jsonArray.isEmpty == false else { return }

        var existingKeys: Set<String> = Set(
            profile.profiles.map { profile in
                normalizedSocialKey(network: profile.network, username: profile.username, url: profile.url)
            }
        )

        for entry in jsonArray where entry.type == .dictionary {
            let network = entry["network"].string?.trimmed() ?? ""
            let username = entry["username"].string?.trimmed() ?? ""
            let url = entry["url"].string?.trimmed() ?? ""

            guard network.isEmpty == false || username.isEmpty == false || url.isEmpty == false else {
                continue
            }

            let key = normalizedSocialKey(network: network, username: username, url: url)
            guard existingKeys.contains(key) == false else { continue }
            existingKeys.insert(key)

            let social = ApplicantSocialProfile(network: network, username: username, url: url, applicant: profile)
            profile.profiles.append(social)
        }
    }

    private func normalizedSocialKey(network: String, username: String, url: String) -> String {
        [network.lowercased(), username.lowercased(), url.lowercased()].joined(separator: "|")
    }
}
