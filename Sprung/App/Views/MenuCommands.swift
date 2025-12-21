//
//  MenuCommands.swift
//  Sprung
//
//  Menu command definitions and notifications for the application.
//
import Foundation
import SwiftUI
import SwiftData

// MARK: - FocusedValue for Knowledge Cards Visibility
/// Allows menu commands to read and toggle the Knowledge Cards pane visibility
struct KnowledgeCardsVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var knowledgeCardsVisible: Binding<Bool>? {
        get { self[KnowledgeCardsVisibleKey.self] }
        set { self[KnowledgeCardsVisibleKey.self] = newValue }
    }
}

// MARK: - Knowledge Cards Menu Item
/// Menu item to open the Knowledge Cards browser
struct KnowledgeCardsMenuItem: View {
    var body: some View {
        Button("Knowledge Cards...") {
            NotificationCenter.default.post(name: .toggleKnowledgeCards, object: nil)
        }
        .keyboardShortcut("k", modifiers: [.command, .option])
    }
}

// MARK: - Menu Command Notifications
/// Central list of notifications bridging AppKit menu/toolbar commands into the SwiftUI layer.
extension Notification.Name {
    // Job Application Commands
    static let newJobApp = Notification.Name("newJobApp")
    static let bestJob = Notification.Name("bestJob")
    static let toggleKnowledgeCards = Notification.Name("toggleKnowledgeCards")
    // Resume Commands
    static let customizeResume = Notification.Name("customizeResume")
    static let clarifyCustomize = Notification.Name("clarifyCustomize")
    static let optimizeResume = Notification.Name("optimizeResume")
    static let showResumeInspector = Notification.Name("showResumeInspector")
    // Cover Letter Commands
    static let generateCoverLetter = Notification.Name("generateCoverLetter")
    static let reviseCoverLetter = Notification.Name("reviseCoverLetter")
    static let batchCoverLetter = Notification.Name("batchCoverLetter")
    static let bestCoverLetter = Notification.Name("bestCoverLetter")
    static let committee = Notification.Name("committee")
    static let showCoverLetterInspector = Notification.Name("showCoverLetterInspector")
    // Text-to-Speech Commands
    static let startSpeaking = Notification.Name("startSpeaking")
    static let stopSpeaking = Notification.Name("stopSpeaking")
    static let restartSpeaking = Notification.Name("restartSpeaking")
    // Analysis Commands
    static let analyzeApplication = Notification.Name("analyzeApplication")
    // Interview Commands
    static let startOnboardingInterview = Notification.Name("startOnboardingInterview")
    // SearchOps Commands
    static let showSearchOps = Notification.Name("showSearchOps")
    // Window Commands (for toolbar buttons)
    static let showSettings = Notification.Name("showSettings")
    static let showApplicantProfile = Notification.Name("showApplicantProfile")
    static let showTemplateEditor = Notification.Name("showTemplateEditor")
    static let showExperienceEditor = Notification.Name("showExperienceEditor")
    static let showWritingContextBrowser = Notification.Name("showWritingContextBrowser")
    // Menu-to-Toolbar Bridge Commands (for programmatically triggering toolbar buttons)
    static let triggerBestJobButton = Notification.Name("triggerBestJobButton")
    static let triggerCustomizeButton = Notification.Name("triggerCustomizeButton")
    static let triggerClarifyingQuestionsButton = Notification.Name("triggerClarifyingQuestionsButton")
    static let triggerGenerateCoverLetterButton = Notification.Name("triggerGenerateCoverLetterButton")
    static let triggerReviseCoverLetterButton = Notification.Name("triggerReviseCoverLetterButton")
    static let triggerTTSButton = Notification.Name("triggerTTSButton")
    static let triggerTTSStart = Notification.Name("triggerTTSStart")
    static let triggerTTSStop = Notification.Name("triggerTTSStop")
    static let triggerTTSRestart = Notification.Name("triggerTTSRestart")
    // Export Commands
    static let exportResumePDF = Notification.Name("exportResumePDF")
    static let exportResumeText = Notification.Name("exportResumeText")
    static let exportResumeJSON = Notification.Name("exportResumeJSON")
    static let exportCoverLetterPDF = Notification.Name("exportCoverLetterPDF")
    static let exportCoverLetterText = Notification.Name("exportCoverLetterText")
    static let exportAllCoverLetters = Notification.Name("exportAllCoverLetters")
    static let exportApplicationPacket = Notification.Name("exportApplicationPacket")
    // Settings/Configuration
    static let apiKeysChanged = Notification.Name("apiKeysChanged")
}
