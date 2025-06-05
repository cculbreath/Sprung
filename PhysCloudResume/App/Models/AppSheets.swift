//
//  AppSheets.swift
//  PhysCloudResume
//

import Foundation

/// Centralized sheet and UI state management for the main app window
/// Replaces individual Bool bindings with a single organized struct
struct AppSheets {
    var showApplicationReview = false
    var showResumeReview = false
    var showClarifyingQuestions = false
    var showChooseBestCoverLetter = false
    var showMultiModelChooseBest = false
    var showBatchCoverLetter = false
    
    // UI state that was previously in ResumeButtons
    var showResumeInspector = false
    var showCoverLetterInspector = false
}