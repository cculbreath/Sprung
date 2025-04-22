import Foundation
import SwiftData
import SwiftOpenAI

@Model
class CoverLetter: Identifiable, Hashable {
    var jobApp: JobApp? = nil
    @Attribute(.unique) var id: UUID = UUID() // Explicit id field
    var createdDate: Date = Date()
    var moddedDate: Date = Date()
    // Editable name of the cover letter, shown in pickers and exports
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
                fatalError("Failed to decode messageHistory: \(error.localizedDescription)")
            }
        }
        set {
            do {
                encodedMessageHistory = try JSONEncoder().encode(newValue)

            } catch {
                fatalError("Failed to encode messageHistory: \(error.localizedDescription)")
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
    var sequenceNumber: Int {
        guard let app = jobApp else { return 0 }
        let sortedLetters = app.coverLetters.sorted { $0.createdDate < $1.createdDate }
        guard let index = sortedLetters.firstIndex(where: { $0.id == self.id }) else { return 0 }
        return index + 1
    }

    /// Converts a positive integer into letters: 1->A, 2->B, ..., 27->AA, etc.
    private static func letterLabel(for number: Int) -> String {
        guard number > 0 else { return "" }
        var n = number
        var label = ""
        while n > 0 {
            let rem = (n - 1) % 26
            if let scalar = UnicodeScalar(65 + rem) {
                label = String(scalar) + label
            }
            n = (n - 1) / 26
        }
        return label
    }

    /// A friendly name prefixed with its alphabetic option and the custom name
    var sequencedName: String {
        let letter = Self.letterLabel(for: sequenceNumber)
        return "Option \(letter)\(name.isEmpty ? "" : ": \(name)")"
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

    // Make MessageRole conform to Codable
    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
        case none
    }
}
