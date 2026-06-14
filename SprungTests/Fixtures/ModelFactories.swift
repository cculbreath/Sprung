//
//  ModelFactories.swift
//  SprungTests
//
//  Shared, compile-safe factories for the most common SwiftData models. Keep these small
//  and dependency-light; richer, phase-specific fixtures (populated ExperienceDefaults
//  with work/education entries, TreeNode trees, template manifests) belong in the owning
//  phase's own fixture file so parallel work never contends on this file.
//
//  Convention: `Fixtures.makeX(...)` returns an *unattached* model. Pass a context to
//  attach it, e.g. `let p = ctx.insert(Fixtures.makeApplicantProfile())`, or use the
//  `InMemoryStoreCase.insert(_:)` helper.
//

import Foundation
@testable import Sprung

enum Fixtures {

    /// A fully-populated applicant profile with deterministic, assertable values.
    static func makeApplicantProfile(
        name: String = "Ada Lovelace",
        label: String = "Software Engineer",
        email: String = "ada@example.com",
        phone: String = "(555) 010-0101",
        city: String = "London",
        state: String = "England",
        countryCode: String = "GB"
    ) -> ApplicantProfile {
        ApplicantProfile(
            name: name,
            label: label,
            summary: "Pioneering engineer focused on correctness and clarity.",
            address: "1 Analytical Way",
            city: city,
            state: state,
            zip: "SW1A",
            countryCode: countryCode,
            websites: "example.com",
            email: email,
            phone: phone
        )
    }

    /// An empty experience-defaults aggregate. Phase 2 builds populated variants (with
    /// work/skills drafts) in its own fixture file once it has read the Draft types.
    static func makeEmptyExperienceDefaults(seedCreated: Bool = false) -> ExperienceDefaults {
        let defaults = ExperienceDefaults()
        defaults.seedCreated = seedCreated
        return defaults
    }
}
