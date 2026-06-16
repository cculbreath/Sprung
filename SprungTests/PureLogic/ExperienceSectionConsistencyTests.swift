//
//  ExperienceSectionConsistencyTests.swift
//  SprungTests
//
//  Drift guard for the resume-section field set, which is enumerated
//  independently across four hierarchies:
//    1. ExperienceDrafts          (the canonical Swift structs / persisted shape)
//    2. ExperienceSchema.sections (the section-browser UI field tree)
//    3. ExperienceSectionCodec    (the JSON wire format: encode/decode)
//    4. ExperienceDefaultsToTree+Sections (the render tree)
//
//  Adding a field to one but forgetting another would silently drop it on that
//  path. Rather than collapse the four into one descriptor (high-risk, low
//  payoff for a stable schema), these tests make divergence impossible to ship:
//  for every array section they assert Drafts (via Mirror) == ExperienceSchema
//  == codec wire keys == a FROZEN wire baseline. The frozen baseline is the
//  "did you mean to change the wire format?" checkpoint — it also catches a
//  self-consistent rename that a round-trip alone would miss (backward-compat
//  with already-persisted ExperienceDefaults).
//
//  Hierarchy #4 (the tree builder) needs a manifest + Resume, so it is guarded
//  separately by the RenderPipeline tests; it uses the same wire keys and would
//  break visibly on divergence.
//
//  Pure value types only (Codable drafts + JSON) — no SwiftData model touched.
//

import XCTest
import SwiftyJSON
@testable import Sprung

final class ExperienceSectionConsistencyTests: XCTestCase {

    // MARK: - Frozen wire baseline

    /// The exact JSON key vocabulary each array section is expected to emit.
    /// Note `projects` uses `entity` (not `organization`) — see the rename test.
    /// Changing this set is a deliberate wire-format change; update it knowingly.
    private static let expectedWireKeys: [ExperienceSectionKey: Set<String>] = [
        .work: ["name", "position", "location", "url", "startDate", "endDate", "summary", "highlights"],
        .volunteer: ["organization", "position", "url", "startDate", "endDate", "summary", "highlights"],
        .education: ["institution", "url", "studyType", "area", "startDate", "endDate", "score", "courses"],
        .projects: ["name", "description", "startDate", "endDate", "url", "entity", "type", "highlights", "keywords", "roles"],
        .skills: ["name", "level", "keywords"],
        .awards: ["title", "date", "awarder", "summary"],
        .certificates: ["name", "date", "issuer", "url"],
        .publications: ["name", "publisher", "releaseDate", "url", "summary"],
        .languages: ["language", "fluency"],
        .interests: ["name", "keywords"],
        .references: ["name", "reference", "url"]
    ]

    /// The 11 array-backed sections (excludes `.custom`, which is bespoke key/value).
    private static let arraySections: [ExperienceSectionKey] = Array(expectedWireKeys.keys)

    // MARK: - Cross-hierarchy agreement

    func testCodecWireKeysMatchFrozenBaseline() {
        let draft = Self.makeFullyPopulatedDraft()
        for section in Self.arraySections {
            let expected = Self.expectedWireKeys[section]!
            XCTAssertEqual(codecWireKeys(section, in: draft), expected,
                           "codec wire keys for \(section.rawValue) drifted from the frozen baseline")
        }
    }

    func testSchemaFieldKeysMatchFrozenBaseline() {
        for section in Self.arraySections {
            let expected = Self.expectedWireKeys[section]!
            XCTAssertEqual(schemaWireKeys(section), expected,
                           "ExperienceSchema field set for \(section.rawValue) drifted — add/remove the field in BOTH the schema and the codec")
        }
    }

    func testDraftPropertiesMatchFrozenBaseline() {
        for (section, element) in Self.sampleElements {
            let expected = Self.expectedWireKeys[section]!
            XCTAssertEqual(modelWireKeys(forElement: element, section: section), expected,
                           "the \(section.rawValue) Draft struct has a property with no codec/schema wiring (or vice versa)")
        }
    }

    // MARK: - Codec behavior contracts (current real behavior, not necessarily ideal)

    func testProjectOrganizationUsesEntityWireKey() {
        // The Swift property `ProjectExperienceDraft.organization` is bridged to
        // the JSON key `entity` on both encode and decode — a deliberate,
        // consistently-applied indirection (not a bug).
        var project = ProjectExperienceDraft()
        project.name = "Rover"
        project.organization = "NASA"
        var draft = ExperienceDefaultsDraft()
        draft.isProjectsEnabled = true
        draft.projects = [project]

        let codec = ExperienceSectionCodecs.all.first { $0.key == .projects }
        let encoded = codec?.encodeSection(from: draft)?.first
        XCTAssertEqual(encoded?["entity"] as? String, "NASA", "organization must encode under the `entity` wire key")
        XCTAssertNil(encoded?["organization"], "the Swift property name must not leak into the wire format")

        let decoded = ExperienceDefaultsDecoder.draft(from: JSON(["projects": [["entity": "NASA"]]]))
        XCTAssertEqual(decoded.projects.first?.organization, "NASA", "`entity` must decode back into organization")
    }

    func testSummaryAndDescriptionAreDecodedVerbatimWhileOtherFieldsTrim() {
        // CURRENT CONTRACT: scalar fields are trimmed on decode, EXCEPT prose
        // fields (work/volunteer/award/publication `summary`, project
        // `description`) which preserve edge whitespace verbatim. Pinned so a
        // future descriptor refactor can't silently flip it.
        let work = ExperienceDefaultsDecoder.draft(from: JSON(["work": [["name": "  Acme  ", "summary": "  multi\nline  "]]]))
        XCTAssertEqual(work.work.first?.name, "Acme", "name is trimmed on decode")
        XCTAssertEqual(work.work.first?.summary, "  multi\nline  ", "summary is decoded verbatim (not trimmed)")

        let project = ExperienceDefaultsDecoder.draft(from: JSON(["projects": [["name": "R", "description": "  spaced  "]]]))
        XCTAssertEqual(project.projects.first?.description, "  spaced  ", "project description is decoded verbatim")
    }

    func testPartiallyPopulatedEntryOmitsBlankFields() {
        var work = WorkExperienceDraft()
        work.name = "Acme"   // only one field set; the rest stay blank
        var draft = ExperienceDefaultsDraft()
        draft.isWorkEnabled = true
        draft.work = [work]

        let encoded = ExperienceSectionCodecs.all.first { $0.key == .work }?.encodeSection(from: draft)?.first
        XCTAssertEqual(encoded?["name"] as? String, "Acme")
        XCTAssertNil(encoded?["location"], "blank fields must be omitted from the wire format, not emitted as empty strings")
        XCTAssertNil(encoded?["summary"])
        XCTAssertNil(encoded?["highlights"])
    }

    // MARK: - Full-seed wire round-trip (id-independent)

    func testFullSeedRoundTripIsWireIdentity() {
        // encode -> decode -> encode must reproduce the same wire dictionary.
        // Compared at the wire level (not via Draft Equatable) because decode
        // mints fresh UUIDs, which encode drops — so this is id-independent and
        // catches dropped fields / asymmetric encode-vs-decode wiring.
        let draft = Self.makeFullyPopulatedDraft()
        let seed = ExperienceDefaultsEncoder.makeSeedDictionary(from: draft)
        let roundTripped = ExperienceDefaultsDecoder.draft(from: JSON(seed))
        let seed2 = ExperienceDefaultsEncoder.makeSeedDictionary(from: roundTripped)
        XCTAssertEqual(seed as NSDictionary, seed2 as NSDictionary,
                       "a fully-populated seed must survive encode -> decode -> encode byte-for-byte at the wire level")
    }

    // MARK: - Helpers

    private func codecWireKeys(_ section: ExperienceSectionKey, in draft: ExperienceDefaultsDraft) -> Set<String> {
        guard let codec = ExperienceSectionCodecs.all.first(where: { $0.key == section }),
              let first = codec.encodeSection(from: draft)?.first else { return [] }
        return Set(first.keys)
    }

    private func schemaWireKeys(_ section: ExperienceSectionKey) -> Set<String> {
        guard let schemaSection = ExperienceSchema.sections.first(where: { $0.key == section }) else { return [] }
        return Set(schemaSection.nodes.map { node in
            switch node.kind {
            case .field(let name): return name
            case .group(let name, _): return name
            }
        })
    }

    private func modelWireKeys(forElement element: Any, section: ExperienceSectionKey) -> Set<String> {
        var keys = Set(Mirror(reflecting: element).children.compactMap { $0.label }).subtracting(["id"])
        // The codec bridges ProjectExperienceDraft.organization -> wire key `entity`.
        if section == .projects, keys.remove("organization") != nil {
            keys.insert("entity")
        }
        return keys
    }

    // MARK: - Fixtures (every field populated with a clean, edge-trimmed value)

    private static let sampleElements: [(ExperienceSectionKey, Any)] = [
        (.work, makeWork()),
        (.volunteer, makeVolunteer()),
        (.education, makeEducation()),
        (.projects, makeProject()),
        (.skills, makeSkill()),
        (.awards, makeAward()),
        (.certificates, makeCertificate()),
        (.publications, makePublication()),
        (.languages, makeLanguage()),
        (.interests, makeInterest()),
        (.references, makeReference())
    ]

    private static func makeFullyPopulatedDraft() -> ExperienceDefaultsDraft {
        var draft = ExperienceDefaultsDraft()
        draft.isWorkEnabled = true; draft.work = [makeWork()]
        draft.isVolunteerEnabled = true; draft.volunteer = [makeVolunteer()]
        draft.isEducationEnabled = true; draft.education = [makeEducation()]
        draft.isProjectsEnabled = true; draft.projects = [makeProject()]
        draft.isSkillsEnabled = true; draft.skills = [makeSkill()]
        draft.isAwardsEnabled = true; draft.awards = [makeAward()]
        draft.isCertificatesEnabled = true; draft.certificates = [makeCertificate()]
        draft.isPublicationsEnabled = true; draft.publications = [makePublication()]
        draft.isLanguagesEnabled = true; draft.languages = [makeLanguage()]
        draft.isInterestsEnabled = true; draft.interests = [makeInterest()]
        draft.isReferencesEnabled = true; draft.references = [makeReference()]
        draft.isCustomEnabled = true
        draft.customFields = [CustomFieldValue(key: "objective", values: ["Land a great role"])]
        return draft
    }

    private static func makeWork() -> WorkExperienceDraft {
        var w = WorkExperienceDraft()
        w.name = "Acme"; w.position = "Engineer"; w.location = "Austin"; w.url = "https://acme.test"
        w.startDate = "2020-01"; w.endDate = "2022-01"; w.summary = "Led the platform team."
        w.highlights = [HighlightDraft(text: "Shipped the thing")]
        return w
    }

    private static func makeVolunteer() -> VolunteerExperienceDraft {
        var v = VolunteerExperienceDraft()
        v.organization = "Helpers"; v.position = "Mentor"; v.url = "https://vol.test"
        v.startDate = "2019"; v.endDate = "2020"; v.summary = "Mentored students."
        v.highlights = [VolunteerHighlightDraft(text: "Ran workshops")]
        return v
    }

    private static func makeEducation() -> EducationExperienceDraft {
        var e = EducationExperienceDraft()
        e.institution = "MIT"; e.url = "https://mit.test"; e.area = "Computer Science"; e.studyType = "BS"
        e.startDate = "2012"; e.endDate = "2016"; e.score = "3.9"
        e.courses = [CourseDraft(name: "Algorithms")]
        return e
    }

    private static func makeProject() -> ProjectExperienceDraft {
        var p = ProjectExperienceDraft()
        p.name = "Rover"; p.description = "An autonomous robot."; p.startDate = "2021"; p.endDate = "2022"
        p.url = "https://rover.test"; p.organization = "NASA"; p.type = "personal"
        p.highlights = [ProjectHighlightDraft(text: "Built the nav stack")]
        p.keywords = [KeywordDraft(keyword: "Swift")]
        p.roles = [RoleDraft(role: "Lead")]
        return p
    }

    private static func makeSkill() -> SkillExperienceDraft {
        var s = SkillExperienceDraft()
        s.name = "Programming"; s.level = "Expert"
        s.keywords = [KeywordDraft(keyword: "Swift")]
        return s
    }

    private static func makeAward() -> AwardExperienceDraft {
        var a = AwardExperienceDraft()
        a.title = "Best Paper"; a.date = "2021"; a.awarder = "ACM"; a.summary = "For the research."
        return a
    }

    private static func makeCertificate() -> CertificateExperienceDraft {
        var c = CertificateExperienceDraft()
        c.name = "AWS Certified"; c.date = "2020"; c.issuer = "Amazon"; c.url = "https://aws.test"
        return c
    }

    private static func makePublication() -> PublicationExperienceDraft {
        var p = PublicationExperienceDraft()
        p.name = "On Robots"; p.publisher = "IEEE"; p.releaseDate = "2021"; p.url = "https://pub.test"; p.summary = "A paper."
        return p
    }

    private static func makeLanguage() -> LanguageExperienceDraft {
        var l = LanguageExperienceDraft()
        l.language = "English"; l.fluency = "Native"
        return l
    }

    private static func makeInterest() -> InterestExperienceDraft {
        var i = InterestExperienceDraft()
        i.name = "Chess"; i.keywords = [KeywordDraft(keyword: "Strategy")]
        return i
    }

    private static func makeReference() -> ReferenceExperienceDraft {
        var r = ReferenceExperienceDraft()
        r.name = "Jane Doe"; r.reference = "A great engineer."; r.url = "https://ref.test"
        return r
    }
}
