import Foundation
import SwiftData

/// Assessment data for multi-model cover letter evaluation
struct AssessmentData: Codable {
    var voteCount: Int = 0
    var scoreCount: Int = 0
    var hasBeenAssessed: Bool = false
}

/// Committee feedback summary for a cover letter
struct CommitteeFeedbackSummary: Codable {
    let letterId: String
    let summaryOfModelAnalysis: String
    let pointsAwarded: [ModelPointsAwarded]
    let modelVotes: [ModelVote]
}

/// Points awarded by a specific model
struct ModelPointsAwarded: Codable {
    let model: String
    let points: Int
}

/// Individual model vote tracking
struct ModelVote: Codable {
    let model: String
    let votedForLetterId: String
    let reasoning: String?
}

/// Structured summary response for committee analysis
struct CommitteeSummaryResponse: Codable {
    let letterAnalyses: [LetterAnalysis]
}

/// Analysis for a specific letter from the committee
struct LetterAnalysis: Codable {
    let letterId: String
    let summaryOfModelAnalysis: String
    let pointsAwarded: [ModelPointsAwarded]
    let modelVotes: [ModelVote]
}

@Model
class CoverLetter: Identifiable, Hashable {
    var jobApp: JobApp? = nil
    @Attribute(.unique) var id: UUID = UUID() // Explicit id field

    /// Stores the OpenAI response ID for server-side conversation state
    // MARK: - Conversation Management (ChatCompletions API)
    
    /// Clears the conversation context for this cover letter
    @MainActor
    func clearConversationContext() {
        // Note: Conversation management now handled by LLMService.shared
        Logger.debug("Cover letter conversation context clear requested - handled by LLMService")
    }

    var createdDate: Date = Date()
    var moddedDate: Date = Date()
    // Editable name of the cover letter, shown in pickers and exports.
    // This will now store the persistent "Option X: Model Name, Revision"
    var name: String = ""
    var content: String = ""
    var generated: Bool = false
    var includeResumeRefs: Bool = false
    // The AI model used to generate this cover letter
    var generationModel: String? = nil
    var encodedEnabledRefs: Data? // Store as Data
    var encodedMessageHistory: Data? // Store as Data
    var currentMode: CoverAiMode? = CoverAiMode.none
    var editorPrompt: CoverLetterPrompts.EditorPrompts = CoverLetterPrompts.EditorPrompts.zissner
    
    /// Indicates this is the chosen submission draft (star indicator)
    var isChosenSubmissionDraft: Bool = false
    
    /// Multi-model assessment data (stored as encoded data to avoid schema changes)
    var encodedAssessmentData: Data? // Stores AssessmentData as JSON
    
    /// Committee feedback summary (stored as encoded data)
    var encodedCommitteeFeedback: Data? // Stores CommitteeFeedbackSummary as JSON
    
    /// Generation metadata: sources used at time of generation (stored as encoded data)
    var encodedGenerationSources: Data? // Stores [CoverRef] as JSON
    
    /// Generation metadata: resume background state at time of generation
    var generationUsedResumeRefs: Bool = false
    var modDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
        return dateFormatter.string(from: moddedDate)
    }

    // Computed properties to decode arrays
    var enabledRefs: [CoverRef] {
        get {
            guard let data = encodedEnabledRefs else { return [] }
            return (try? JSONDecoder().decode([CoverRef].self, from: data)) ?? []
        }
        set {
            encodedEnabledRefs = try? JSONEncoder().encode(newValue)
        }
    }

    var messageHistory: [MessageParams] {
        get {
            guard let data = encodedMessageHistory else {
                return []
            }
            do {
                return try JSONDecoder().decode([MessageParams].self, from: data)
            } catch {
                Logger.debug("Failed to decode messageHistory: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                encodedMessageHistory = try JSONEncoder().encode(newValue)

            } catch {
                Logger.debug("Failed to encode messageHistory: \(error.localizedDescription)")
            }
        }
    }
    
    /// Multi-model assessment data computed properties
    var assessmentData: AssessmentData {
        get {
            guard let data = encodedAssessmentData else {
                return AssessmentData()
            }
            do {
                return try JSONDecoder().decode(AssessmentData.self, from: data)
            } catch {
                Logger.debug("Failed to decode assessmentData: \(error.localizedDescription)")
                return AssessmentData()
            }
        }
        set {
            do {
                encodedAssessmentData = try JSONEncoder().encode(newValue)
            } catch {
                Logger.debug("Failed to encode assessmentData: \(error.localizedDescription)")
            }
        }
    }
    
    var voteCount: Int {
        get { assessmentData.voteCount }
        set { 
            var data = assessmentData
            data.voteCount = newValue
            assessmentData = data
        }
    }
    
    var scoreCount: Int {
        get { assessmentData.scoreCount }
        set { 
            var data = assessmentData
            data.scoreCount = newValue
            assessmentData = data
        }
    }
    
    var hasBeenAssessed: Bool {
        get { assessmentData.hasBeenAssessed }
        set { 
            var data = assessmentData
            data.hasBeenAssessed = newValue
            assessmentData = data
        }
    }
    
    /// Committee feedback summary computed properties
    var committeeFeedback: CommitteeFeedbackSummary? {
        get {
            guard let data = encodedCommitteeFeedback else {
                return nil
            }
            do {
                return try JSONDecoder().decode(CommitteeFeedbackSummary.self, from: data)
            } catch {
                Logger.debug("Failed to decode committeeFeedback: \(error.localizedDescription)")
                return nil
            }
        }
        set {
            do {
                encodedCommitteeFeedback = try JSONEncoder().encode(newValue)
            } catch {
                Logger.debug("Failed to encode committeeFeedback: \(error.localizedDescription)")
            }
        }
    }
    
    /// Generation sources computed properties (read-only snapshot of sources at generation time)
    var generationSources: [CoverRef] {
        get {
            guard let data = encodedGenerationSources else {
                return []
            }
            do {
                return try JSONDecoder().decode([CoverRef].self, from: data)
            } catch {
                Logger.debug("Failed to decode generationSources: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                encodedGenerationSources = try JSONEncoder().encode(newValue)
            } catch {
                Logger.debug("Failed to encode generationSources: \(error.localizedDescription)")
            }
        }
    }

    init(
        enabledRefs: [CoverRef],
        jobApp: JobApp?
    ) {
        encodedEnabledRefs = try? JSONEncoder().encode(enabledRefs)
        self.jobApp = jobApp ?? nil
    }

    var backgroundItemsString: String {
        return enabledRefs.filter { $0.type == CoverRefType.backgroundFact }
            .map { $0.content }.joined(separator: "\n\n")
    }

    var writingSamplesString: String {
        return enabledRefs.filter { $0.type == CoverRefType.writingSample }
            .map { $0.content }.joined(separator: "\n\n")
    }

    /// 1-based index of this cover letter within its job application (ordered by creation date)
    /// This remains dynamic and is used for assigning the *initial* "Option X" label.
    var sequenceNumber: Int {
        guard let app = jobApp else { return 0 }
        let sortedLetters = app.coverLetters.sorted { $0.createdDate < $1.createdDate }
        guard let index = sortedLetters.firstIndex(where: { $0.id == self.id }) else { return 0 }
        return index + 1
    }

    /// Converts a positive integer into letters: 1->A, 2->B, ..., 27->AA, etc.
    static func letterLabel(for number: Int) -> String {
        guard number > 0 else { return "" }
        var n = number
        var label = ""
        while n > 0 {
            let rem = (n - 1) % 26
            if let scalar = UnicodeScalar(65 + rem) { // 65 is 'A'
                label = String(scalar) + label
            }
            n = (n - 1) / 26
        }
        return label
    }

    /// A friendly name for display. If `name` is set (which it should be for generated letters),
    /// it will be used directly. Otherwise, provides a fallback.
    var sequencedName: String {
        if name.isEmpty {
            if generated {
                // Fallback for generated but somehow unnamed letter.
                // Uses current dynamic sequence number for the "Option X" part.
                return "Generated \(Self.letterLabel(for: sequenceNumber))"
            } else {
                // For a truly blank, ungenerated, unnamed letter.
                // Uses current dynamic sequence number for the "Option X" part.
                return "Ungenerated Draft \(Self.letterLabel(for: sequenceNumber))"
            }
        }
        // If name is not empty, it's expected to contain the persistent "Option X: ..." label.
        return name
    }

    /// Extract the option letter from the cover letter name
    var optionLetter: String {
        // Extract the part before the colon for option letter
        let nameParts = name.split(separator: ":", maxSplits: 1)
        if !nameParts.isEmpty {
            if let optionWord = nameParts[0].split(separator: " ").first,
               optionWord == "Option",
               let letterPart = nameParts[0].split(separator: " ").last
            {
                return String(letterPart)
            }
        }
        return ""
    }

    /// Get the next available option letter based on all letters in the job app
    /// This ensures we never reuse an option letter, even when others are deleted
    func getNextOptionLetter() -> String {
        guard let jobApp = jobApp else { return "A" }

        // Get all used option letters, including from deleted letters
        let usedLetters = Set(jobApp.coverLetters.compactMap { letter -> String in
            return letter.optionLetter
        }.filter { !$0.isEmpty })

        // Start with position 1 (A) and increment until we find an unused letter
        var position = 1
        while true {
            let currentLetter = CoverLetter.letterLabel(for: position)
            if !usedLetters.contains(currentLetter) {
                return currentLetter
            }
            position += 1
        }
    }

    /// Get editable portion of the name (part after the colon)
    var editableName: String {
        let nameParts = name.split(separator: ":", maxSplits: 1)
        if nameParts.count > 1 {
            return String(nameParts[1]).trimmingCharacters(in: .whitespaces)
        }
        return name // If no colon, return the full name
    }

    /// Set editable portion of the name while preserving the Option prefix
    func setEditableName(_ newContent: String) {
        let nameParts = name.split(separator: ":", maxSplits: 1)
        if nameParts.count > 1 {
            // Preserve the "Option X:" prefix
            let prefix = String(nameParts[0])
            name = "\(prefix): \(newContent)"
        } else {
            // No prefix found, set the name directly
            name = newContent
        }
    }
    
    /// Marks this cover letter as the chosen submission draft, clearing the flag from all others
    func markAsChosenSubmissionDraft() {
        guard let jobApp = jobApp else { return }
        
        // Clear the flag from all other cover letters for this job
        for letter in jobApp.coverLetters {
            if letter.id != self.id {
                letter.isChosenSubmissionDraft = false
            }
        }
        
        // Set this one as chosen
        self.isChosenSubmissionDraft = true
    }
}

@Model
class MessageParams: Identifiable, Codable {
    var id: String = UUID().uuidString
    var content: String
    var role: MessageRole

    init(content: String, role: MessageRole) {
        self.content = content
        self.role = role
    }

    // Manual Codable implementation
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case role
    }

    // Required initializer for Decodable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        role = try container.decode(MessageRole.self, forKey: .role)
    }

    // Required function for Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(role, forKey: .role)
    }

    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
        case none
    }
}
