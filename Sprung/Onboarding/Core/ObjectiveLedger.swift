import Foundation

enum ObjectiveStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case skipped
}

struct ObjectiveDescriptor {
    let id: String
    let label: String
    let phase: InterviewPhase
    let initialStatus: ObjectiveStatus
    let initialSource: String
    let details: [String: String]?

    init(
        id: String,
        label: String,
        phase: InterviewPhase,
        initialStatus: ObjectiveStatus = .pending,
        initialSource: String = "system",
        details: [String: String]? = nil
    ) {
        self.id = id
        self.label = label
        self.phase = phase
        self.initialStatus = initialStatus
        self.initialSource = initialSource
        self.details = details
    }

    func makeEntry(date: Date = Date.distantPast) -> ObjectiveEntry {
        ObjectiveEntry(
            id: id,
            label: label,
            status: initialStatus,
            source: initialSource,
            updatedAt: date,
            details: details,
            notes: nil
        )
    }
}

struct ObjectiveEntry: Codable, Equatable {
    let id: String
    var label: String
    var status: ObjectiveStatus
    var source: String
    var updatedAt: Date
    var details: [String: String]?
    var notes: String?
}

struct ObjectiveLedgerSnapshot {
    let entries: [ObjectiveEntry]

    var signature: String {
        entries
            .sorted { $0.id < $1.id }
            .map {
                let detailString = ($0.details ?? [:])
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "|")
                let notePart = $0.notes ?? ""
                return "\($0.id)#\($0.status.rawValue)#\($0.updatedAt.timeIntervalSince1970)#\($0.source)#\(detailString)#\(notePart)"
            }
            .joined(separator: "||")
    }

    func formattedSummary(dateFormatter: DateFormatter) -> String {
        guard !entries.isEmpty else { return "" }
        return entries
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(6)
            .map { entry in
                let timestamp = entry.updatedAt == Date.distantPast ? "n/a" : dateFormatter.string(from: entry.updatedAt)
                return "\(entry.label)=\(entry.status.rawValue) (via \(entry.source), \(timestamp))"
            }
            .joined(separator: "; ")
    }
}

enum ObjectiveCatalog {
    static func objectives(for phase: InterviewPhase) -> [ObjectiveDescriptor] {
        switch phase {
        case .phase1CoreFacts:
            return phaseOneDescriptors
        case .phase2DeepDive:
            return phaseTwoDescriptors
        case .phase3WritingCorpus:
            return phaseThreeDescriptors
        case .complete:
            return []
        }
    }

    private static let phaseOneDescriptors: [ObjectiveDescriptor] = [
        ObjectiveDescriptor(
            id: "applicant_profile",
            label: "Applicant profile objective",
            phase: .phase1CoreFacts
        ),
        ObjectiveDescriptor(
            id: "skeleton_timeline",
            label: "Skeleton timeline objective",
            phase: .phase1CoreFacts
        ),
        ObjectiveDescriptor(
            id: "enabled_sections",
            label: "Enabled sections objective",
            phase: .phase1CoreFacts
        ),
        ObjectiveDescriptor(
            id: "contact_source_selected",
            label: "Contact source selected",
            phase: .phase1CoreFacts
        ),
        ObjectiveDescriptor(
            id: "contact_data_collected",
            label: "Contact data collected",
            phase: .phase1CoreFacts
        ),
        ObjectiveDescriptor(
            id: "contact_data_validated",
            label: "Contact data validated",
            phase: .phase1CoreFacts
        ),
        ObjectiveDescriptor(
            id: "contact_photo_collected",
            label: "Contact photo collected",
            phase: .phase1CoreFacts,
            initialStatus: .pending
        )
    ]

    private static let phaseTwoDescriptors: [ObjectiveDescriptor] = [
        ObjectiveDescriptor(
            id: "interviewed_one_experience",
            label: "Experience interview completed",
            phase: .phase2DeepDive
        ),
        ObjectiveDescriptor(
            id: "one_card_generated",
            label: "Knowledge card generated",
            phase: .phase2DeepDive
        )
    ]

    private static let phaseThreeDescriptors: [ObjectiveDescriptor] = [
        ObjectiveDescriptor(
            id: "one_writing_sample",
            label: "Writing sample collected",
            phase: .phase3WritingCorpus
        ),
        ObjectiveDescriptor(
            id: "dossier_complete",
            label: "Dossier completed",
            phase: .phase3WritingCorpus
        )
    ]
}
