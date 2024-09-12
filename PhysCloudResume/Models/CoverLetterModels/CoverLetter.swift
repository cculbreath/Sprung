import Foundation
import SwiftData
import SwiftOpenAI

@Model
class CoverLetter {
  var jobApp: JobApp
  var createdDate: Date = Date()
  var moddedDate: Date = Date()
  var content: String = ""
  var generated: Bool = false
  var encodedEnabledRefs: Data? // Store as Data
  var encodedMessageHistory: Data? // Store as Data
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
      guard let data = encodedMessageHistory else { return [] }
      return (try? JSONDecoder().decode([MessageParams].self, from: data)) ?? []
    }
    set {
      encodedMessageHistory = try? JSONEncoder().encode(newValue)
    }
  }

  init(
    enabledRefs: [CoverRef],
    jobApp: JobApp
  ) {
    self.encodedEnabledRefs = try? JSONEncoder().encode(enabledRefs)
    self.jobApp = jobApp
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
    case user = "user"
    case assistant = "assistant"
    case none = "none"
  }
}
