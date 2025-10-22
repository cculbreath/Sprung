import Foundation
import SwiftyJSON

enum OnboardingWizardStep: Int, CaseIterable, Identifiable {
    case introduction
    case resumeIntake
    case artifactDiscovery
    case writingCorpus
    case wrapUp

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .introduction:
            return "Introduction"
        case .resumeIntake:
            return "Résumé Intake"
        case .artifactDiscovery:
            return "Artifact Discovery"
        case .writingCorpus:
            return "Writing Corpus"
        case .wrapUp:
            return "Review & Finish"
        }
    }

    var subtitle: String {
        switch self {
        case .introduction:
            return "Learn how the onboarding interview works."
        case .resumeIntake:
            return "Confirm parsed résumé or LinkedIn data."
        case .artifactDiscovery:
            return "Capture high-impact work and supporting materials."
        case .writingCorpus:
            return "Build a writing style profile from samples."
        case .wrapUp:
            return "Review captured data and next steps."
        }
    }
}

enum OnboardingWizardStepStatus: Equatable {
    case pending
    case current
    case completed
}

struct OnboardingUploadRequest: Identifiable, Equatable {
    enum UploadKind: String {
        case resume
        case artifact
        case writingSample
        case linkedIn
        case generic

        init(raw: String) {
            switch raw.lowercased() {
            case "resume", "résumé", "cv":
                self = .resume
            case "artifact", "supporting_artifact", "evidence":
                self = .artifact
            case "writing", "writing_sample", "writingSample":
                self = .writingSample
            case "linkedin", "linked_in", "profile":
                self = .linkedIn
            default:
                self = .generic
            }
        }
    }

    struct Metadata: Equatable {
        let accepts: [String]
        let instructions: String
        let title: String
        let allowMultiple: Bool
        let followupTool: String?
        let followupArgs: JSON?
    }

    let id: UUID
    let toolCallId: String
    let kind: UploadKind
    let metadata: Metadata

    init(
        toolCallId: String,
        kind: UploadKind,
        metadata: Metadata
    ) {
        self.id = UUID()
        self.toolCallId = toolCallId
        self.kind = kind
        self.metadata = metadata
    }

    static func fromToolCall(_ call: OnboardingToolCall) -> OnboardingUploadRequest {
        let kind = UploadKind(raw: call.arguments["kind"].stringValue)
        let acceptValues = (
            call.arguments["accepts"].arrayValue +
            call.arguments["acceptedFileTypes"].arrayValue
        )
        .compactMap { $0.string?.lowercased() }
        let accepts = acceptValues.reduce(into: [String]()) { result, next in
            if !result.contains(next) {
                result.append(next)
            }
        }
        let instructions = call.arguments["instructions"].string ??
            call.arguments["prompt"].string ??
            "Please provide the requested file."
        let title = call.arguments["title"].string ??
            call.arguments["label"].string ??
            defaultTitle(for: kind)
        let allowMultiple = call.arguments["allow_multiple"].bool ?? false
        let followupTool = call.arguments["followup_tool"].string
        let followupArgs = call.arguments["followup_args"]

        return OnboardingUploadRequest(
            toolCallId: call.identifier,
            kind: kind,
            metadata: Metadata(
                accepts: accepts,
                instructions: instructions,
                title: title,
                allowMultiple: allowMultiple,
                followupTool: followupTool,
                followupArgs: followupArgs
            )
        )
    }

    private static func defaultTitle(for kind: UploadKind) -> String {
        switch kind {
        case .resume:
            return "Upload Résumé"
        case .artifact:
            return "Upload Artifact"
        case .writingSample:
            return "Upload Writing Sample"
        case .linkedIn:
            return "Provide LinkedIn URL"
        case .generic:
            return "Upload File"
        }
    }
}
