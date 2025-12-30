import Foundation
import SwiftUI
enum ExperienceSectionKey: String, CaseIterable, Identifiable {
    case summary
    case work
    case volunteer
    case education
    case projects
    case skills
    case awards
    case certificates
    case publications
    case languages
    case interests
    case references
    case custom
    var id: String { rawValue }
    var metadata: ExperienceSectionMetadata {
        ExperienceSectionMetadata.forKey(self)
    }
}
struct ExperienceSchemaNode: Identifiable {
    enum NodeKind {
        case field(String)
        case group(String, [ExperienceSchemaNode])
    }
    let id = UUID()
    let kind: NodeKind
}
struct ExperienceSchemaSection: Identifiable {
    let key: ExperienceSectionKey
    let nodes: [ExperienceSchemaNode]
    var id: ExperienceSectionKey { key }
    var metadata: ExperienceSectionMetadata { key.metadata }
}
enum ExperienceSchema {
    static let sections: [ExperienceSchemaSection] = [
        ExperienceSchemaSection(
            key: .work,
            nodes: [
                field("name"),
                field("position"),
                field("location"),
                field("url"),
                field("startDate"),
                field("endDate"),
                field("summary"),
                group("highlights", children: [field("text")])
            ]
        ),
        ExperienceSchemaSection(
            key: .volunteer,
            nodes: [
                field("organization"),
                field("position"),
                field("url"),
                field("startDate"),
                field("endDate"),
                field("summary"),
                group("highlights", children: [field("text")])
            ]
        ),
        ExperienceSchemaSection(
            key: .education,
            nodes: [
                field("institution"),
                field("url"),
                field("studyType"),
                field("area"),
                field("startDate"),
                field("endDate"),
                field("score"),
                group("courses", children: [field("name")])
            ]
        ),
        ExperienceSchemaSection(
            key: .projects,
            nodes: [
                field("name"),
                field("description"),
                field("startDate"),
                field("endDate"),
                field("url"),
                field("entity"),
                field("type"),
                group("highlights", children: [field("text")]),
                group("keywords", children: [field("keyword")]),
                group("roles", children: [field("role")])
            ]
        ),
        ExperienceSchemaSection(
            key: .skills,
            nodes: [
                field("name"),
                field("level"),
                group("keywords", children: [field("keyword")])
            ]
        ),
        ExperienceSchemaSection(
            key: .awards,
            nodes: [
                field("title"),
                field("date"),
                field("awarder"),
                field("summary")
            ]
        ),
        ExperienceSchemaSection(
            key: .certificates,
            nodes: [
                field("name"),
                field("date"),
                field("issuer"),
                field("url")
            ]
        ),
        ExperienceSchemaSection(
            key: .publications,
            nodes: [
                field("name"),
                field("publisher"),
                field("releaseDate"),
                field("url"),
                field("summary")
            ]
        ),
        ExperienceSchemaSection(
            key: .languages,
            nodes: [
                field("language"),
                field("fluency")
            ]
        ),
        ExperienceSchemaSection(
            key: .interests,
            nodes: [
                field("name"),
                group("keywords", children: [field("keyword")])
            ]
        ),
        ExperienceSchemaSection(
            key: .references,
            nodes: [
                field("name"),
                field("reference"),
                field("url")
            ]
        ),
        ExperienceSchemaSection(
            key: .custom,
            nodes: [
                field("key"),
                field("values")
            ]
        )
    ]
    private static func field(_ name: String) -> ExperienceSchemaNode {
        ExperienceSchemaNode(kind: .field(name))
    }
    private static func group(_ name: String, children: [ExperienceSchemaNode]) -> ExperienceSchemaNode {
        ExperienceSchemaNode(kind: .group(name, children))
    }
}
struct ExperienceSectionMetadata {
    let title: String
    let subtitle: String?
    let addButtonTitle: String
    let isEnabledKeyPath: WritableKeyPath<ExperienceDefaultsDraft, Bool>
    func toggleBinding(in draft: Binding<ExperienceDefaultsDraft>) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue[keyPath: isEnabledKeyPath] },
            set: { newValue in
                draft.wrappedValue[keyPath: isEnabledKeyPath] = newValue
            }
        )
    }
}
extension ExperienceSectionMetadata {
    static func forKey(_ key: ExperienceSectionKey) -> ExperienceSectionMetadata {
        switch key {
        case .summary:
            return ExperienceSectionMetadata(
                title: "Summary",
                subtitle: nil,
                addButtonTitle: "⊕ Add Summary",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isSummaryEnabled
            )
        case .work:
            return ExperienceSectionMetadata(
                title: "Work Experience",
                subtitle: "Default roles and accomplishments for new resumes",
                addButtonTitle: "⊕ Add Work History",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isWorkEnabled
            )
        case .volunteer:
            return ExperienceSectionMetadata(
                title: "Volunteer Experience",
                subtitle: nil,
                addButtonTitle: "⊕ Add Volunteer Work",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isVolunteerEnabled
            )
        case .education:
            return ExperienceSectionMetadata(
                title: "Education",
                subtitle: "Preconfigured studies, courses, and achievements",
                addButtonTitle: "⊕ Add Education",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isEducationEnabled
            )
        case .projects:
            return ExperienceSectionMetadata(
                title: "Projects",
                subtitle: nil,
                addButtonTitle: "⊕ Add Project",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isProjectsEnabled
            )
        case .skills:
            return ExperienceSectionMetadata(
                title: "Skills",
                subtitle: nil,
                addButtonTitle: "⊕ Add Skill",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isSkillsEnabled
            )
        case .awards:
            return ExperienceSectionMetadata(
                title: "Awards",
                subtitle: nil,
                addButtonTitle: "⊕ Add Award",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isAwardsEnabled
            )
        case .certificates:
            return ExperienceSectionMetadata(
                title: "Certificates",
                subtitle: nil,
                addButtonTitle: "⊕ Add Certificate",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isCertificatesEnabled
            )
        case .publications:
            return ExperienceSectionMetadata(
                title: "Publications",
                subtitle: nil,
                addButtonTitle: "⊕ Add Publication",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isPublicationsEnabled
            )
        case .languages:
            return ExperienceSectionMetadata(
                title: "Languages",
                subtitle: nil,
                addButtonTitle: "⊕ Add Language",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isLanguagesEnabled
            )
        case .interests:
            return ExperienceSectionMetadata(
                title: "Interests",
                subtitle: nil,
                addButtonTitle: "⊕ Add Interest",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isInterestsEnabled
            )
        case .references:
            return ExperienceSectionMetadata(
                title: "References",
                subtitle: nil,
                addButtonTitle: "⊕ Add Reference",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isReferencesEnabled
            )
        case .custom:
            return ExperienceSectionMetadata(
                title: "Custom Fields",
                subtitle: "Defaults for custom template fields (e.g., job titles)",
                addButtonTitle: "⊕ Add Custom Field",
                isEnabledKeyPath: \ExperienceDefaultsDraft.isCustomEnabled
            )
        }
    }
}
