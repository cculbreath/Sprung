//
//  NetworkingModels.swift
//  Sprung
//
//  Models for Networking Coach feature.
//  See sprung_networking_coach_spec.md Section 3 for full definitions.
//

import Foundation
import SwiftData

// MARK: - Event Types

enum NetworkingEventType: String, Codable, CaseIterable {
    case meetup = "Meetup"
    case happyHour = "Happy Hour"
    case conference = "Conference"
    case workshop = "Workshop"
    case techTalk = "Tech Talk"
    case openHouse = "Open House"
    case careerFair = "Career Fair"
    case panelDiscussion = "Panel Discussion"
    case hackathon = "Hackathon"
    case virtualEvent = "Virtual Event"
    case coffeeChat = "Coffee Chat"
    case other = "Other"

    var icon: String {
        switch self {
        case .meetup: return "person.3"
        case .happyHour: return "wineglass"
        case .conference: return "building.2"
        case .workshop: return "hammer"
        case .techTalk: return "mic"
        case .openHouse: return "door.left.hand.open"
        case .careerFair: return "person.crop.rectangle.stack"
        case .panelDiscussion: return "rectangle.3.group.bubble"
        case .hackathon: return "laptopcomputer"
        case .virtualEvent: return "video"
        case .coffeeChat: return "cup.and.saucer"
        case .other: return "calendar"
        }
    }
}

enum AttendanceSize: String, Codable, CaseIterable {
    case intimate = "Intimate (<10)"
    case small = "Small (10-30)"
    case medium = "Medium (30-100)"
    case large = "Large (100-300)"
    case massive = "Massive (300+)"
}

enum EventPipelineStatus: String, Codable, CaseIterable {
    case discovered = "Discovered"
    case evaluating = "Evaluating"
    case recommended = "Recommended"
    case planned = "Planned"
    case skipped = "Skipped"
    case attended = "Attended"
    case debriefed = "Debriefed"
    case cancelled = "Cancelled"
    case missed = "Missed"

    var isActive: Bool {
        switch self {
        case .discovered, .evaluating, .recommended, .planned:
            return true
        default:
            return false
        }
    }
}

enum AttendanceRecommendation: String, Codable, CaseIterable {
    case strongYes = "Strongly Recommend"
    case yes = "Recommend"
    case maybe = "Consider"
    case skip = "Skip"

    var icon: String {
        switch self {
        case .strongYes: return "star.fill"
        case .yes: return "checkmark.circle"
        case .maybe: return "questionmark.circle"
        case .skip: return "xmark.circle"
        }
    }
}

enum EventRating: Int, Codable, CaseIterable {
    case waste = 1
    case poor = 2
    case okay = 3
    case good = 4
    case excellent = 5
}

enum DiscoverySource: String, Codable {
    case webSearch = "Web Search"
    case calendarDetected = "Calendar Detected"
    case manual = "Manually Added"
    case contactSuggested = "Contact Suggested"
    case recurring = "Recurring Event"
}

// MARK: - Networking Event Opportunity

@Model
class NetworkingEventOpportunity: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    // Event Details
    var name: String = ""
    var eventDescription: String?
    var date: Date = Date()
    var time: String?
    var endTime: String?
    var location: String = ""
    var locationAddress: String?
    var isVirtual: Bool = false
    var virtualLink: String?
    var url: String = ""
    var organizer: String?
    var organizerUrl: String?

    // Classification
    var eventType: NetworkingEventType = NetworkingEventType.meetup
    var estimatedAttendance: AttendanceSize = AttendanceSize.medium
    var cost: String?
    var requiresRegistration: Bool = false
    var registrationDeadline: Date?

    // Pipeline Status
    var status: EventPipelineStatus = EventPipelineStatus.discovered

    // LLM Evaluation
    var llmRecommendation: AttendanceRecommendation?
    var llmRationale: String?
    var expectedValue: String?
    var concernsJSON: String?  // JSON encoded [String]

    // Planning
    var goal: String?
    var pitchScript: String?
    var talkingPointsJSON: String?  // JSON encoded [TalkingPoint]
    var targetCompaniesJSON: String?  // JSON encoded [TargetCompanyContext]
    var conversationStartersJSON: String?  // JSON encoded [String]
    var thingsToAvoidJSON: String?  // JSON encoded [String]
    var calendarEventId: String?

    // Execution
    var attended: Bool = false
    var attendedAt: Date?
    var actualDurationMinutes: Int?

    // Debrief
    var contactCount: Int = 0
    var eventNotes: String?
    var eventRating: EventRating?
    var wouldRecommend: Bool?
    var whatWorked: String?
    var whatDidntWork: String?
    var followUpActionsJSON: String?  // JSON encoded [FollowUpAction]

    // Discovery Metadata
    var discoveredAt: Date = Date()
    var discoveredVia: DiscoverySource = DiscoverySource.webSearch
    var searchQueryUsed: String?
    var relevanceReason: String?
    var targetCompaniesLikelyJSON: String?  // JSON encoded [String]

    init() {}

    var needsDebrief: Bool { attended && status != .debriefed }

    var daysUntilEvent: Int? {
        guard date > Date() else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day
    }

    // JSON decode helpers
    var concerns: [String]? {
        get {
            guard let json = concernsJSON else { return nil }
            return try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        }
        set {
            concernsJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var conversationStarters: [String]? {
        get {
            guard let json = conversationStartersJSON else { return nil }
            return try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        }
        set {
            conversationStartersJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var thingsToAvoid: [String]? {
        get {
            guard let json = thingsToAvoidJSON else { return nil }
            return try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        }
        set {
            thingsToAvoidJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var talkingPoints: [TalkingPoint]? {
        get {
            guard let json = talkingPointsJSON else { return nil }
            return try? JSONDecoder().decode([TalkingPoint].self, from: Data(json.utf8))
        }
        set {
            talkingPointsJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var targetCompanies: [TargetCompanyContext]? {
        get {
            guard let json = targetCompaniesJSON else { return nil }
            return try? JSONDecoder().decode([TargetCompanyContext].self, from: Data(json.utf8))
        }
        set {
            targetCompaniesJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var followUpActions: [FollowUpAction]? {
        get {
            guard let json = followUpActionsJSON else { return nil }
            return try? JSONDecoder().decode([FollowUpAction].self, from: Data(json.utf8))
        }
        set {
            followUpActionsJSON = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }
}

// MARK: - Relationship Types

enum RelationshipType: String, Codable, CaseIterable {
    case formerColleague = "Former Colleague"
    case formerManager = "Former Manager"
    case formerDirectReport = "Former Direct Report"
    case classmate = "Classmate"
    case professor = "Professor/Mentor"
    case metAtEvent = "Met at Event"
    case onlineConnection = "Online Connection"
    case coldOutreach = "Cold Outreach"
    case recruiter = "Recruiter"
    case referral = "Referred by Someone"
    case friend = "Friend"
    case familyFriend = "Family Friend"
    case other = "Other"
}

enum ContactWarmth: String, Codable, CaseIterable {
    case hot = "Hot"
    case warm = "Warm"
    case cold = "Cold"
    case dormant = "Dormant"
}

enum RelationshipHealth: String, CaseIterable {
    case healthy = "Healthy"
    case needsAttention = "Needs Attention"
    case decaying = "Decaying"
    case dormant = "Dormant"
    case new = "New"

    var icon: String {
        switch self {
        case .healthy: return "heart.fill"
        case .needsAttention: return "exclamationmark.triangle"
        case .decaying: return "arrow.down.heart"
        case .dormant: return "moon.zzz"
        case .new: return "sparkles"
        }
    }
}

// MARK: - Networking Contact

@Model
class NetworkingContact: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    // Identity
    var name: String = ""
    var firstName: String?
    var lastName: String?
    var company: String?
    var title: String?
    var department: String?

    // Contact Information
    var email: String?
    var phone: String?
    var linkedInUrl: String?
    var twitterHandle: String?
    var otherContactInfo: String?

    // Relationship Context
    var relationship: RelationshipType = RelationshipType.metAtEvent
    var howWeMet: String?
    var metAt: String?
    var metOn: Date?
    var introducedById: UUID?

    // Relationship State
    var warmth: ContactWarmth = ContactWarmth.warm
    var lastContactAt: Date?
    var lastContactType: String?
    var nextActionAt: Date?
    var nextAction: String?

    // Notes
    var notes: String = ""
    var conversationNotes: String?

    // Value Indicators
    var canReferToJSON: String?  // JSON encoded [String]
    var hasOfferedToHelp: Bool = false
    var helpOffered: String?
    var isRecruiter: Bool = false
    var isHiringManager: Bool = false
    var isAtTargetCompany: Bool = false

    // Tracking
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isFromCalendar: Bool = false
    var linkedJobAppIdsJSON: String?  // JSON encoded [UUID]
    var totalInteractions: Int = 0

    // Link to event where we met
    var metAtEventId: UUID?

    init() {}

    init(name: String, company: String? = nil, relationship: RelationshipType = RelationshipType.metAtEvent) {
        self.name = name
        self.company = company
        self.relationship = relationship
    }

    var daysSinceContact: Int? {
        guard let last = lastContactAt else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    var relationshipHealth: RelationshipHealth {
        guard let days = daysSinceContact else { return .new }

        switch warmth {
        case .hot:
            if days <= 7 { return .healthy }
            if days <= 21 { return .needsAttention }
            return .decaying
        case .warm:
            if days <= 30 { return .healthy }
            if days <= 60 { return .needsAttention }
            return .decaying
        case .cold:
            return .dormant
        case .dormant:
            return .dormant
        }
    }

    var displayName: String {
        if let first = firstName, let last = lastName {
            return "\(first) \(last)"
        }
        return name
    }

    var companyAndTitle: String? {
        switch (company, title) {
        case let (c?, t?): return "\(t) at \(c)"
        case let (c?, nil): return c
        case let (nil, t?): return t
        case (nil, nil): return nil
        }
    }
}

// MARK: - Networking Interaction

enum InteractionType: String, Codable, CaseIterable {
    case email = "Email"
    case linkedInMessage = "LinkedIn Message"
    case linkedInComment = "LinkedIn Comment"
    case phoneCall = "Phone Call"
    case videoCall = "Video Call"
    case coffee = "Coffee/Meal"
    case eventMeeting = "Met at Event"
    case introduction = "Introduction Made"
    case referralGiven = "Referral Given"
    case referralReceived = "Referral Received"
    case informational = "Informational Interview"
    case slackDM = "Slack/Discord DM"
    case textMessage = "Text Message"
    case other = "Other"
}

enum InteractionOutcome: String, Codable, CaseIterable {
    case positive = "Positive"
    case neutral = "Neutral"
    case noResponse = "No Response"
    case declined = "Declined"
    case referralOffered = "Referral Offered"
    case introOffered = "Intro Offered"
    case leadProvided = "Lead Provided"
    case meetingScheduled = "Meeting Scheduled"
}

@Model
class NetworkingInteraction: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var contactId: UUID = UUID()
    var interactionType: InteractionType = InteractionType.other
    var date: Date = Date()
    var notes: String = ""

    var eventId: UUID?
    var calendarEventId: String?
    var isFromCalendar: Bool = false

    var outcome: InteractionOutcome?
    var followUpNeeded: Bool = false
    var followUpAction: String?
    var followUpDate: Date?
    var followUpCompleted: Bool = false

    var messageSubject: String?
    var messageDraft: String?
    var messageSent: Bool = false

    init() {}

    init(contactId: UUID, type: InteractionType, date: Date = Date()) {
        self.contactId = contactId
        self.interactionType = type
        self.date = date
    }
}

// MARK: - Event Feedback (for learning)

@Model
class EventFeedback: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var eventOpportunityId: UUID = UUID()

    // Denormalized for analysis
    var eventType: NetworkingEventType = NetworkingEventType.meetup
    var organizer: String?
    var attendanceSize: AttendanceSize = AttendanceSize.medium
    var wasVirtual: Bool = false
    var cost: String?

    // Outcomes
    var rating: EventRating = EventRating.okay
    var contactsMade: Int = 0
    var qualityContactsMade: Int = 0
    var leadsGenerated: Int = 0
    var wouldRecommend: Bool = false

    var whatWorked: String?
    var whatDidntWork: String?

    var createdAt: Date = Date()

    init() {}
}

// MARK: - Supporting Structs (for JSON encoding in models)

struct TalkingPoint: Codable, Identifiable {
    var id: UUID = UUID()
    var topic: String
    var relevance: String
    var yourAngle: String
}

struct TargetCompanyContext: Codable, Identifiable {
    var id: UUID = UUID()
    var company: String
    var whyRelevant: String
    var recentNews: String?
    var openRoles: [String]?
    var possibleOpeners: [String]
}

struct FollowUpAction: Codable, Identifiable {
    var id: UUID = UUID()
    var contactId: UUID?
    var contactName: String
    var action: String
    var deadline: FollowUpDeadline
    var completed: Bool = false
    var completedAt: Date?
}

enum FollowUpDeadline: String, Codable {
    case within24Hours = "Within 24 hours"
    case within3Days = "Within 3 days"
    case thisWeek = "This week"
    case nextWeek = "Next week"
    case noRush = "No rush"
}
