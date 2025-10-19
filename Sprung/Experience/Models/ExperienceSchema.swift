import Foundation

enum ExperienceSectionKey: String, CaseIterable, Identifiable {
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .work: return "Work"
        case .volunteer: return "Volunteer"
        case .education: return "Education"
        case .projects: return "Projects"
        case .skills: return "Skills"
        case .awards: return "Awards"
        case .certificates: return "Certificates"
        case .publications: return "Publications"
        case .languages: return "Languages"
        case .interests: return "Interests"
        case .references: return "References"
        }
    }

    var addButtonTitle: String {
        switch self {
        case .work: return "⊕ Add Work History"
        case .volunteer: return "⊕ Add Volunteer Work"
        case .education: return "⊕ Add Education"
        case .projects: return "⊕ Add Project"
        case .skills: return "⊕ Add Skill"
        case .awards: return "⊕ Add Award"
        case .certificates: return "⊕ Add Certificate"
        case .publications: return "⊕ Add Publication"
        case .languages: return "⊕ Add Language"
        case .interests: return "⊕ Add Interest"
        case .references: return "⊕ Add Reference"
        }
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
    let id = UUID()
    let key: ExperienceSectionKey
    let title: String
    let nodes: [ExperienceSchemaNode]
}

enum ExperienceSchema {
    static let sections: [ExperienceSchemaSection] = [
        ExperienceSchemaSection(
            key: .work,
            title: "Work Experience",
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
            title: "Volunteer Experience",
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
            title: "Education",
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
            title: "Projects",
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
            title: "Skills",
            nodes: [
                field("name"),
                field("level"),
                group("keywords", children: [field("keyword")])
            ]
        ),
        ExperienceSchemaSection(
            key: .awards,
            title: "Awards",
            nodes: [
                field("title"),
                field("date"),
                field("awarder"),
                field("summary")
            ]
        ),
        ExperienceSchemaSection(
            key: .certificates,
            title: "Certificates",
            nodes: [
                field("name"),
                field("date"),
                field("issuer"),
                field("url")
            ]
        ),
        ExperienceSchemaSection(
            key: .publications,
            title: "Publications",
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
            title: "Languages",
            nodes: [
                field("language"),
                field("fluency")
            ]
        ),
        ExperienceSchemaSection(
            key: .interests,
            title: "Interests",
            nodes: [
                field("name"),
                group("keywords", children: [field("keyword")])
            ]
        ),
        ExperienceSchemaSection(
            key: .references,
            title: "References",
            nodes: [
                field("name"),
                field("reference"),
                field("url")
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
