import Foundation
import SwiftyJSON

/// Imports ExperienceDefaults-compatible values from an existing Resume.
///
/// This maps the resume's mustache rendering context back into the ExperienceDefaults schema:
/// - Sections: work/education/projects/etc are transferred when present.
/// - Custom fields: resume.custom.* -> custom
@MainActor
enum ExperienceDefaultsImportService {
    static func importDraft(from resume: Resume, profile: ApplicantProfile) throws -> ExperienceDefaultsDraft {
        let context = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let contextJSON = JSON(context)

        var payload = JSON()

        for codec in ExperienceSectionCodecs.all {
            let key = codec.key.rawValue
            let value = contextJSON[key]
            if value.type == .array {
                payload[key] = value
            }
        }

        if contextJSON["custom"].type == .dictionary {
            payload["custom"] = contextJSON["custom"]
        }

        return ExperienceDefaultsDecoder.draft(from: payload)
    }

    static func merged(current: ExperienceDefaultsDraft, imported: ExperienceDefaultsDraft) -> ExperienceDefaultsDraft {
        var merged = current

        // Merge section arrays by simple append; leave de-dup to user if needed.
        if imported.isWorkEnabled { merged.isWorkEnabled = true; merged.work.append(contentsOf: imported.work) }
        if imported.isVolunteerEnabled { merged.isVolunteerEnabled = true; merged.volunteer.append(contentsOf: imported.volunteer) }
        if imported.isEducationEnabled { merged.isEducationEnabled = true; merged.education.append(contentsOf: imported.education) }
        if imported.isProjectsEnabled { merged.isProjectsEnabled = true; merged.projects.append(contentsOf: imported.projects) }
        if imported.isSkillsEnabled { merged.isSkillsEnabled = true; merged.skills.append(contentsOf: imported.skills) }
        if imported.isAwardsEnabled { merged.isAwardsEnabled = true; merged.awards.append(contentsOf: imported.awards) }
        if imported.isCertificatesEnabled { merged.isCertificatesEnabled = true; merged.certificates.append(contentsOf: imported.certificates) }
        if imported.isPublicationsEnabled { merged.isPublicationsEnabled = true; merged.publications.append(contentsOf: imported.publications) }
        if imported.isLanguagesEnabled { merged.isLanguagesEnabled = true; merged.languages.append(contentsOf: imported.languages) }
        if imported.isInterestsEnabled { merged.isInterestsEnabled = true; merged.interests.append(contentsOf: imported.interests) }
        if imported.isReferencesEnabled { merged.isReferencesEnabled = true; merged.references.append(contentsOf: imported.references) }

        // Merge custom fields by key.
        if imported.isCustomEnabled {
            merged.isCustomEnabled = true
            var existingByKey: [String: CustomFieldValue] = Dictionary(
                uniqueKeysWithValues: merged.customFields.map { ($0.key.lowercased(), $0) }
            )
            for field in imported.customFields {
                let lower = field.key.lowercased()
                if var existing = existingByKey[lower] {
                    let combined = (existing.values + field.values)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    existing.values = Array(NSOrderedSet(array: combined)) as? [String] ?? combined
                    existingByKey[lower] = existing
                } else {
                    existingByKey[lower] = field
                }
            }
            merged.customFields = existingByKey.values.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        }

        return merged
    }
}

