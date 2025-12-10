//
//  ResumeContextBuilder.swift
//  Sprung
//
//  Unified context builder for resume rendering.
//  Single entry point for all resume context generation.
//
import Foundation
import OrderedCollections

/// Builds the complete Mustache-renderable context for a resume.
///
/// This is the single entry point for generating context used by:
/// - NativePDFGenerator (PDF export)
/// - TextResumeGenerator (plain text export)
/// - Template preview
///
/// Design principles:
/// 1. TreeNode data provides job-specific content
/// 2. ApplicantProfile provides contact/identity info (always fresh at render time)
/// 3. Convention over configuration: basics.* always comes from ApplicantProfile
/// 4. HandlebarsContextAugmentor adds computed fields at the end
@MainActor
enum ResumeContextBuilder {

    // MARK: - Public API

    /// Build complete rendering context for a resume.
    ///
    /// - Parameters:
    ///   - resume: The resume to build context for (contains TreeNode data)
    ///   - profile: The applicant profile (merged into basics.* by convention)
    /// - Returns: Dictionary ready for Mustache template rendering
    /// - Throws: If TreeNode context cannot be built
    /// Standard JSON Resume section keys (not custom)
    private static let standardSectionKeys: Set<String> = [
        "basics", "work", "volunteer", "education", "projects", "skills",
        "awards", "certificates", "publications", "languages", "interests",
        "references", "meta", "styling", "summary", "keys-in-editor"
    ]

    static func buildContext(
        for resume: Resume,
        profile: ApplicantProfile
    ) throws -> [String: Any] {
        // Step 1: Build base context from TreeNode
        var treeContext = try ResumeTemplateDataBuilder.buildContext(from: resume)

        // Step 1.5: Nest custom fields under "custom" key for template compatibility
        // Custom fields are flattened in TreeNode (for editor display) but templates
        // expect them under custom.fieldName
        treeContext = nestCustomFields(in: treeContext)

        // Step 2: Overlay ApplicantProfile onto basics.* (by convention)
        var context = mergeApplicantProfile(profile, into: treeContext)

        // Step 3: Apply section visibility from manifest + resume overrides
        if let template = resume.template,
           let manifest = TemplateManifestLoader.manifest(for: template) {
            applySectionVisibility(to: &context, manifest: manifest, resume: resume)
        }

        // Step 4: Augment with computed fields
        context = HandlebarsContextAugmentor.augment(context)

        return context
    }

    // MARK: - ApplicantProfile Merge (Convention-based)

    /// Merge ApplicantProfile data into context using convention.
    ///
    /// By convention, identity fields ALWAYS come from ApplicantProfile:
    /// - basics.name, basics.email, basics.phone, basics.label
    /// - basics.website / basics.url
    /// - basics.picture / basics.image
    /// - basics.location.* (city, state/region, address, postalCode, countryCode)
    /// - basics.profiles (social links)
    ///
    /// Exception: basics.summary is job-specific and comes from TreeNode.
    /// Profile.summary is only used as fallback if TreeNode has no summary.
    private static func mergeApplicantProfile(
        _ profile: ApplicantProfile,
        into context: [String: Any]
    ) -> [String: Any] {
        var result = context

        // Check for job-specific objective/summary from TreeNode (takes precedence over profile)
        // First check custom.objective (preferred), then legacy summary section
        let customDict = context["custom"] as? [String: Any]
        let customObjective = (customDict?["objective"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let treeSummary = (context["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Exclude profile.summary if we have custom.objective or tree summary
        let hasJobSpecificSummary = (customObjective != nil && !customObjective!.isEmpty) ||
                                    (treeSummary != nil && !treeSummary!.isEmpty)

        // Build profile-sourced basics
        var profileBasics = buildBasicsFromProfile(profile, excludeSummary: hasJobSpecificSummary)

        // If TreeNode has summary (legacy), use that for basics.summary
        if let summary = treeSummary, !summary.isEmpty {
            profileBasics["summary"] = summary
        }

        // Merge into existing basics (profile values take precedence)
        if var existingBasics = result["basics"] as? [String: Any] {
            for (key, value) in profileBasics {
                if let existingDict = existingBasics[key] as? [String: Any],
                   let newDict = value as? [String: Any] {
                    // Merge nested dictionaries (like location)
                    var merged = existingDict
                    for (subKey, subValue) in newDict {
                        merged[subKey] = subValue
                    }
                    existingBasics[key] = merged
                } else {
                    existingBasics[key] = value
                }
            }
            result["basics"] = existingBasics
        } else if !profileBasics.isEmpty {
            result["basics"] = profileBasics
        }

        return result
    }

    /// Build the basics dictionary from ApplicantProfile.
    /// - Parameter excludeSummary: If true, skip summary (use TreeNode summary instead)
    private static func buildBasicsFromProfile(_ profile: ApplicantProfile, excludeSummary: Bool = false) -> [String: Any] {
        var basics: [String: Any] = [:]

        // Name
        if let name = sanitized(profile.name) {
            basics["name"] = name
        }

        // Label (professional title)
        if let label = sanitized(profile.label) {
            basics["label"] = label
        }

        // Summary (only if not excluded - TreeNode summary takes precedence)
        if !excludeSummary, let summary = sanitized(profile.summary) {
            basics["summary"] = summary
        }

        // Contact info
        if let email = sanitized(profile.email) {
            basics["email"] = email
        }

        if let phone = sanitized(profile.phone) {
            basics["phone"] = phone
        }

        // Website (map to both common keys)
        if let website = sanitized(profile.websites) {
            basics["website"] = website
            basics["url"] = website
        }

        // Picture (data URL)
        if let picture = profile.pictureDataURL() {
            basics["picture"] = picture
            basics["image"] = picture
        }

        // Location
        var location: [String: Any] = [:]
        if let address = sanitized(profile.address) {
            location["address"] = address
        }
        if let city = sanitized(profile.city) {
            location["city"] = city
        }
        if let state = sanitized(profile.state) {
            location["state"] = state
            location["region"] = state  // Common alias
        }
        if let zip = sanitized(profile.zip) {
            location["postalCode"] = zip
        }
        if let countryCode = sanitized(profile.countryCode) {
            location["countryCode"] = countryCode
        }
        if !location.isEmpty {
            basics["location"] = location
        }

        // Social profiles
        let profiles = buildProfilesArray(from: profile)
        if !profiles.isEmpty {
            basics["profiles"] = profiles
        }

        return basics
    }

    /// Build the profiles array from ApplicantProfile social links.
    private static func buildProfilesArray(from profile: ApplicantProfile) -> [[String: String]] {
        profile.profiles.compactMap { social -> [String: String]? in
            var entry: [String: String] = [:]
            if let network = sanitized(social.network) {
                entry["network"] = network
            }
            if let username = sanitized(social.username) {
                entry["username"] = username
            }
            if let url = sanitized(social.url) {
                entry["url"] = url
            }
            return entry.isEmpty ? nil : entry
        }
    }

    // MARK: - Section Visibility

    /// Apply section visibility flags from manifest defaults and resume overrides.
    private static func applySectionVisibility(
        to context: inout [String: Any],
        manifest: TemplateManifest,
        resume: Resume
    ) {
        // Start with manifest defaults
        var visibility = manifest.sectionVisibilityDefaults ?? [:]

        // Apply resume-specific overrides
        for (key, value) in resume.sectionVisibilityOverrides {
            visibility[key] = value
        }

        guard !visibility.isEmpty else { return }

        // For each visibility setting, update the corresponding Bool flag
        for (sectionKey, shouldDisplay) in visibility {
            let boolKey = "\(sectionKey)Bool"

            // Determine base visibility (does section have content?)
            let baseVisible: Bool
            if let numeric = context[boolKey] as? NSNumber {
                baseVisible = numeric.boolValue
            } else if let flag = context[boolKey] as? Bool {
                baseVisible = flag
            } else if let value = context[sectionKey] {
                baseVisible = truthy(value)
            } else {
                baseVisible = false
            }

            // Final visibility = has content AND should display
            context[boolKey] = baseVisible && shouldDisplay
        }
    }

    // MARK: - Custom Fields

    /// Nest custom fields under a "custom" key for template compatibility.
    /// Custom fields are flattened in TreeNode (for editor display) but templates
    /// expect them under custom.fieldName (e.g., custom.jobTitles, custom.moreInfo).
    private static func nestCustomFields(in context: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        var customFields: [String: Any] = context["custom"] as? [String: Any] ?? [:]

        for (key, value) in context {
            if standardSectionKeys.contains(key) || key.hasSuffix("Bool") {
                // Standard section or visibility flag - keep at root
                result[key] = value
            } else if key == "custom" {
                // Already a custom container - merge later
                continue
            } else {
                // Custom field - nest under "custom"
                customFields[key] = value
            }
        }

        if !customFields.isEmpty {
            result["custom"] = customFields
        }

        return result
    }

    // MARK: - Helpers

    /// Sanitize a string value (trim whitespace, return nil if empty).
    private static func sanitized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Check if a value is "truthy" for template purposes.
    private static func truthy(_ value: Any) -> Bool {
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let array as [Any]:
            return !array.isEmpty
        case let dict as [String: Any]:
            return !dict.isEmpty
        case let ordered as OrderedDictionary<String, Any>:
            return !ordered.isEmpty
        default:
            return true
        }
    }
}
