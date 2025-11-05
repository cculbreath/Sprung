//
//  OnboardingArtifacts+Alias.swift
//  Sprung
//
//  Canonical type alias for OnboardingArtifacts.
//  The authoritative definition lives in StateCoordinator.OnboardingArtifacts.
//

import Foundation

/// Canonical alias to the single source of truth for onboarding artifacts.
/// All artifact state is managed by StateCoordinator.
typealias OnboardingArtifacts = StateCoordinator.OnboardingArtifacts
