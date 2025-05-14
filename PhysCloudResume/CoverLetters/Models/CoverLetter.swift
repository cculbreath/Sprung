import Foundation
import SwiftData

@Model
class CoverLetter: Identifiable, Hashable {
    var jobApp: JobApp? = nil
    @Attribute(.unique) var id: UUID = UUID() // Explicit id field

    /// Stores the OpenAI response ID for server-side conversation state
    var previousResponseId: String? = nil

    var createdDate: Date = Date()
    var moddedDate: Date = Date()
    // Editable name of the cover letter, shown in pickers and exports.
    // This will now store the persistent "Option X: Model Name, Revision"
    var name: String = ""
    var content: String = ""
    var generated: Bool = false
    var includeResumeRefs: Bool = false
    var encodedEnabledRefs: Data? // Store as Data
    var encodedMessageHistory: Data? // Store as Data
    var currentMode: CoverAiMode? = CoverAiMode.none
    var editorPrompt: CoverLetterPrompts.EditorPrompts = CoverLetterPrompts.EditorPrompts.zissner
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
        let usedLetters = jobApp.coverLetters.compactMap { letter -> String in
            return letter.optionLetter
        }.filter { !$0.isEmpty }

        // Start with 'A'
        let alphabetStart = Character("A").asciiValue ?? 65
        var letterValue: UInt8 = alphabetStart

        // Find the first unused letter
        while true {
            let currentLetter = String(Character(UnicodeScalar(letterValue)))
            if !usedLetters.contains(currentLetter) {
                return currentLetter
            }
            letterValue += 1

            // Extremely unlikely, but in case we run past Z, start with AA
            if letterValue > Character("Z").asciiValue ?? 90 {
                return "AA"
            }
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
